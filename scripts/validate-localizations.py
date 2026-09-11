#!/usr/bin/env python3
"""Reject String Catalog keys without a translated English and Russian unit."""
import json
import pathlib
import sys

catalog_path = pathlib.Path('Resources/Localizable.xcstrings')
whitelist_path = pathlib.Path('scripts/localization-whitelist.txt')
whitelist = {
    line.strip() for line in whitelist_path.read_text().splitlines()
    if line.strip() and not line.lstrip().startswith('#')
}
catalog = json.loads(catalog_path.read_text())
if catalog.get('sourceLanguage') != 'en':
    sys.exit('String Catalog source language must remain en')
errors = []
for key, value in catalog.get('strings', {}).items():
    localizations = value.get('localizations', {})
    en = localizations.get('en', {}).get('stringUnit', {})
    ru = localizations.get('ru', {}).get('stringUnit', {})
    if en.get('state') != 'translated' or not en.get('value'):
        errors.append(f'{key!r}: English must be translated')
    if key not in whitelist and (ru.get('state') != 'translated' or not ru.get('value')):
        errors.append(f'{key!r}: Russian translation is missing or not translated')
if errors:
    sys.exit('String Catalog validation failed:\n' + '\n'.join(errors))
print(f'Localization validation passed: {len(catalog.get("strings", {}))} keys, {len(whitelist)} whitelist entries')
