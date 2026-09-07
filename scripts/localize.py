#!/usr/bin/env python3
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
pairs='''About|О приложении
Action|Действие
Add a resource|Добавить материал
Add morning alarm|Утреннее напоминание
Add reminder group|Добавить группу
Add time|Добавить время
Add to collection|Добавить в коллекцию
Alignment|Выравнивание
All entries|Все записи
App Icon|Значок приложения
Apple Watch|Apple Watch
Author|Автор
Author (optional)|Автор (необязательно)
Available freezes|Доступные заморозки
Background|Фон
Background polling|Фоновый опрос
Backup / Restore|Резервная копия
Backup preview|Предпросмотр копии
Backup restored|Копия восстановлена
Blank-separated paragraphs|Абзацы через пустую строку
Bold|Жирный
Border|Рамка
Cancel|Отмена
Cancel import|Отменить импорт
Center|По центру
Choose a topic|Выберите тему
Choose background photo|Выбрать фото для фона
Choose backup to restore|Выбрать резервную копию
Choose files|Выбрать файлы
Clear|Очистить
Clear history|Очистить историю
Collection name|Название коллекции
Collections|Коллекции
Content|Содержание
Content Preferences|Источники ленты
Copied|Скопировано
Copy text|Скопировать текст
Create a theme|Создать оформление
Create and add|Создать и добавить
Create collection|Создать коллекцию
Daily|Каждый день
Daily content|Мысль дня
Dark overlay|Затемнение
Database|База данных
Days|Дни
Days of reading|Дней чтения
Delete|Удалить
Delete collection|Удалить коллекцию
Delete entry|Удалить запись
Details|Сведения
Detect automatically|Определить автоматически
Diagnostics|Диагностика
Dislike|Не нравится
Disliked content|Не понравилось
Done|Готово
Duplicates in file|Повторы в файле
Edit|Изменить
Edit current theme|Изменить текущее оформление
Edit theme|Редактор оформления
Enable notifications|Разрешить уведомления
Enabled|Включено
English|English
Entries|Записи
Entry text|Текст записи
Evening streak reminder|Вечернее напоминание о чтении
Every 3 hours|Каждые 3 часа
Every day|Каждый день
Every entry|С каждой записью
Existing topic|Существующая тема
Experience|Настройки чтения
Export App Backup|Экспорт резервной копии
Favorite|В избранное
Favorites|Избранное
Favorites only|Только избранное
Fixed|Без смены
Font|Шрифт
Format|Формат
Fortune|Случайная мысль
From|С
Gender identity (optional)|Гендер (необязательно)
General|Основные
Haptics|Тактильный отклик
Home Screen Widgets|Виджеты экрана «Домой»
Horizon light|Свет на горизонте
Hourly|Каждый час
Image saved|Изображение сохранено
Import JSON or CSV|Импорт JSON или CSV
Import as new|Импортировать как новую тему
Import entries|Импортировать записи
Import files|Импорт файлов
Import options|Параметры импорта
Import your words|Импорт ваших записей
Language|Язык
Left|Слева
Library could not open|Не удалось открыть библиотеку
Light color|Цвет света
Load more|Загрузить ещё
Local storage|Память устройства
Lock Screen Widgets|Виджеты экрана блокировки
Longest streak|Лучшая серия
Make topics from Markdown sections|Создать темы из разделов Markdown
Malformed|Ошибочные записи
Medium|Средний
Merge content into library|Добавить записи в библиотеку
Merge files into one topic|Объединить файлы в одну тему
Merge into topic|Добавить в тему
Mix topics or choose a tag|Смешать темы или выбрать тег
Monospaced|Моноширинный
More actions|Другие действия
Morning thought|Утренняя мысль
Mute|Скрыть
Mute a word or phrase|Скрыть слово или фразу
Mute this entry|Скрыть запись
Muted Content|Скрытые записи
Muted words|Скрытые слова
Muted words and phrases|Скрытые слова и фразы
My Content|Мои записи
My theme|Моё оформление
Name|Имя
Needs attention|Требует внимания
Network dependency|Зависимость от сети
New collection name|Название новой коллекции
New widget preset|Новый вариант виджета
Next|Следующая
No account, ads or subscriptions|Без аккаунта, рекламы и подписок
No entries found|Записи не найдены
No sound|Без звука
None|Нет
None for core operation|Для основных функций не нужна
Note|Заметка
OK|ОК
One entry per line|Одна запись в строке
Open LERN on iPhone|Откройте LERN на iPhone
Open LERN to choose your words|Откройте LERN и выберите записи
Open LERN to import your words.|Откройте LERN и импортируйте записи.
Open Settings|Открыть настройки
Open and share|Открыть и поделиться
Order|Порядок
Past Content|История чтения
Pending notifications|Запланировано уведомлений
Pending reminders|Запланировано напоминаний
Personal|Личное
Preview and save wallpaper|Посмотреть и сохранить обои
Private. Offline. Yours.|Личное. Без интернета. Ваше.
Random|Случайно
Read collection|Читать коллекцию
Read from|Источники чтения
Read selected source|Читать выбранное
Read this topic|Читать тему
Refresh|Обновление
Refresh diagnostics|Обновить диагностику
Regular|Обычный
Reminder groups|Группы напоминаний
Reminders|Напоминания
Remove photo|Убрать фото
Replace library|Заменить библиотеку
Replace library and settings|Заменить библиотеку и настройки
Replace topic entries|Заменить записи темы
Resource|Материал
Resources / Books|Материалы и книги
Restore|Вернуть
Reveal a thought|Открыть мысль
Right|Справа
Rotate themes|Смена оформления
Rounded|Скруглённый
Save|Сохранить
Save image|Сохранить изображение
Save or share image|Сохранить или отправить изображение
Schedule|Расписание
Scheduled through|Запланировано до
Sequential|По порядку
Serif|С засечками
Set up in Shortcuts|Настройка в «Командах»
Share image|Поделиться изображением
Share text|Поделиться текстом
Share your thought|Поделиться мыслью
Show LERN watermark|Подпись LERN на изображении
Show buttons|Показывать кнопки
Shuffle without repeats|Вперемешку без повторов
Sound|Звук
Source (optional)|Источник (необязательно)
Spread across a time range|Распределить по времени
Square|Квадрат
Start reading|Начать чтение
Story|История
Streak|Серия чтения
Sync to Watch|Передать на часы
System|Системный
System default|Системный звук
TXT layout|Структура TXT
Tag or section (optional)|Тег или раздел (необязательно)
Tags, separated by commas|Теги через запятую
Text color|Цвет текста
Theme|Оформление
Theme Mix|Смена оформлений
Theme name|Название оформления
Themes|Оформления
Time|Время
Title|Название
Topics|Темы
Topics and collections|Темы и коллекции
Track my streak|Считать серию чтения
Try again|Повторить
Try original sample thoughts|Попробовать примеры LERN
Type of Content|Источник записей
URL (optional)|Ссылка (необязательно)
Until|До
Valid entries|Корректные записи
Wallpaper|Обои
Wallpapers|Обои
Weekdays|Будни
Weekends|Выходные
Weight|Насыщенность
Widget preset|Вариант виджета
Widget presets|Варианты виджетов
Widget type|Вид виджета
Word or phrase|Слово или фраза
Write a thought|Записать мысль
Your collections|Ваши коллекции
Your files stay on this device|Ваши файлы хранятся локально
Your library|Ваша библиотека
Your space|Ваше пространство
Your words|Ваши слова
Previous|Предыдущая
Profile|Профиль
Remove favorite|Убрать из избранного
Keep your own words close.|Пусть ваши мысли будут рядом.
No matching entries|Нет подходящих записей
Bring a text file, a collection of ideas, or a thought you want to return to.|Добавьте текстовый файл, подборку идей или мысль, к которой хочется вернуться.
Choose another topic or review muted content in your profile.|Выберите другую тему или проверьте скрытые записи в профиле.
Opening your library|Открываем библиотеку
Something needs attention|Требует внимания
Text, author, source or tag|Текст, автор, источник или тег
Entries|Записи
Search results|Результаты поиска
Edit thought|Изменить мысль
Reminder group|Группа напоминаний
Morning alarm|Утреннее напоминание
On|Вкл.
Off|Выкл.
viewed|Прочитано
scheduled|Запланировано
opened|Открыто
Horizon|Горизонт
Minimal Black|Минимальный чёрный
Minimal White|Минимальный белый
Gradient|Градиент
Quote Mark|Кавычки
Warm|Тёплый
Cool|Холодный
A thought for you|Мысль для вас
30 minutes|30 минут
4:5|4:5
Version 1.0 · iOS 18+|Версия 1.0 · iOS 18+
Русский|Русский'''
long_pairs='''A day counts when you read a thought in the feed. A freeze automatically covers one missed day. Earn one freeze every seven reading days, up to three. Opening the app twice never counts as two days.|День засчитывается, когда вы читаете запись в ленте. Заморозка автоматически сохраняет серию за один пропущенный день. За каждые семь дней чтения вы получаете одну заморозку, максимум — три. Повторное открытие приложения не добавляет день.
Add LERN to your Lock Screen from the wallpaper editor. This source is independent of Home Screen presets.|Добавьте LERN на экран блокировки в редакторе обоев. Его источник не зависит от виджетов экрана «Домой».
Add LERN's Get Wallpaper action.|Добавьте действие LERN «Получить обои».
Add a LERN widget from your Home Screen, then edit it to choose a saved preset. iOS decides the final refresh time.|Добавьте виджет LERN на экран «Домой» и выберите сохранённый вариант в его настройках. Точное время обновления определяет iOS.
Allow photo access in Settings to save images. You can also use Share image and Save to Files.|Разрешите добавление фото в настройках. Также можно выбрать «Поделиться изображением» и сохранить его в «Файлы».
Available apps appear in the iOS share sheet.|Доступные приложения появятся в системном меню отправки.
Choose a Watch source in LERN on your iPhone, then tap Sync to Watch.|Выберите источник для часов в LERN на iPhone и нажмите «Передать на часы».
Choose your Lock Screen and the automation's run behavior.|Выберите экран блокировки и способ запуска автоматизации.
Create a personal Time of Day automation in Shortcuts.|Создайте личную автоматизацию «Время суток» в приложении «Команды».
Exact duplicates already in the library reuse the original entry, keeping favorites and collections.|Точные повторы связываются с существующей записью. Избранное и коллекции сохраняются.
Import Markdown, TXT, CSV, TSV, JSON or JSONL. Each file becomes a topic. Up to 100 MB and 100,000 entries per file.|Импортируйте Markdown, TXT, CSV, TSV, JSON или JSONL. Каждый файл станет темой. Лимит файла — 100 МБ и 100 000 записей.
Import cancelled. Completed files remain in your library.|Импорт отменён. Уже обработанные файлы остались в библиотеке.
Keep text readable over your photo using the overlay and text color.|Настройте затемнение и цвет текста, чтобы запись легко читалась поверх фото.
LERN creates the image locally. Only your Shortcuts automation changes the wallpaper. iOS may require confirmation for your chosen automation settings.|LERN создаёт изображение на устройстве. Обои меняет ваша автоматизация в «Командах». В зависимости от настроек iOS может потребовать подтверждение.
Let your own words meet you during the day.|Возвращайтесь к своим мыслям в течение дня.
Matching entries will be hidden from the feed, reminders, widgets and Watch.|Совпадающие записи будут скрыты в ленте, напоминаниях, виджетах и на часах.
Medium and large widgets support favorite and open/share actions. Refresh timing is managed by iOS.|Средние и большие виджеты позволяют добавить в избранное и открыть запись для отправки. Частоту обновления контролирует iOS.
Merge adds missing content and collections while keeping your current settings.|Объединение добавляет недостающие записи и коллекции, сохраняя текущие настройки.
Notifications are turned off in iOS Settings.|Уведомления выключены в настройках iOS.
Notifications follow Apple's normal iPhone and Watch mirroring rules.|Уведомления показываются на iPhone и часах по стандартным правилам Apple.
Pass its image to Set Wallpaper Photo.|Передайте изображение действию «Установить фото обоев».
Sample thoughts, icons and sounds are original. This app is not affiliated with Monkey Taps.|Примеры мыслей, значки и звуки созданы для LERN. Приложение не связано с Monkey Taps.
Save a complete local copy of your library, themes, photos, favorites, collections and settings. Choose where it goes in Files.|Сохраните полную копию библиотеки, оформлений, фото, избранного, коллекций и настроек. Место сохранения выберите в «Файлах».
Scheduled means iOS accepted a request, not proof that it was shown. Opened is recorded only after a notification or deep link is opened.|«Запланировано» означает, что iOS приняла запрос, но не подтверждает показ. «Открыто» записывается после открытия уведомления или ссылки.
Showing the first 200 matching entries. Search to narrow this collection.|Показаны первые 200 подходящих записей. Уточните поиск, чтобы найти остальные.
Some reminder groups overlap. Both will be scheduled. Edit the times if you prefer more space between them.|Время некоторых групп совпадает. Обе будут запланированы. Измените время, если нужен интервал между напоминаниями.
The Watch receives a local selection of up to 100 entries from this source. Open LERN on your iPhone after changing it. No internet is required.|Часы получают до 100 записей из этого источника. После его изменения откройте LERN на iPhone. Интернет не нужен.
This alarm is a local notification. It follows Focus and silent-mode settings and does not behave like a critical system alarm.|Это локальное уведомление. Оно учитывает фокусирование и беззвучный режим и не работает как критический системный будильник.
This entry is no longer in your library.|Этой записи больше нет в библиотеке.
This source applies only to the screen you are editing. Other sources stay independent.|Этот источник применяется только к текущему экрану. Остальные настраиваются независимо.
Your own words, always close. A private, local reading library.|Ваши мысли всегда рядом. Личная библиотека на вашем устройстве.
Your reading history will appear here.|Здесь появится история чтения.
iOS keeps a limited queue. Open LERN to replenish it. At 10 reminders a day, 60 reminders cover about 6 days.|Очередь iOS ограничена. Открывайте LERN для её пополнения. При 10 напоминаниях в день очередь из 60 запросов рассчитана примерно на 6 дней.'''
translations=dict(line.split('|',1) for line in (pairs+'\n'+long_pairs).splitlines() if '|' in line)
translations.update({'A little room\nto think.':'Немного места\nдля мысли.','Give your thoughts\na place to breathe.':'Дайте мыслям\nсвободное пространство.','Soft chime %lld':'Мягкий звон %lld','%lld reminders a day':'Напоминаний в день: %lld','%lld days':'Дней: %lld','Imported %lld entries. Reused %lld duplicates.':'Добавлено записей: %lld. Повторов: %lld.','Streak: %lld days':'Серия чтения: %lld дн.'})
strings={key:{'localizations':{'en':{'stringUnit':{'state':'translated','value':key}},'ru':{'stringUnit':{'state':'translated','value':value}}}} for key,value in translations.items()}
(root/'Resources/Localizable.xcstrings').write_text(json.dumps({'sourceLanguage':'en','version':'1.0','strings':strings},ensure_ascii=False,indent=2)+'\n')
