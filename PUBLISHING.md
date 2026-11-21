# Выпуск Ai ReaStems на GitHub

- Предлагаемое имя репозитория — `Ai-ReaStems`.
- Короткое описание — «Локальное разделение аудио на стемы в REAPER на базе stems.cpp».
- Ветка репозитория по умолчанию — `main`. В ней находятся README и два скриншота в `Media/screenshots/`.
- Тег GitHub Release — `v0.2.5`. Заголовок — **Ai ReaStems 0.2.5**. Текст — из
  [RELEASE_NOTES.md](RELEASE_NOTES.md).
- В **Release assets** приложите `Ai_ReaStems_Setup_0.2.5_Windows.zip`
  и `Ai_ReaStems_Setup_0.2.5_Windows.zip.sha256` из `D:\!Release`.

Содержимое репозитория включает исходники и зависимые файлы для сборки
установщика. Для пользователей укажите установочный ZIP из **Release
assets**. Модели, отчёты и рабочий кэш хранятся локально у пользователей.

Сформировать манифест и новый архив для будущей версии можно так.

```powershell
python tools/prepare_payload.py
python tools/package_release.py --output-dir 'D:\!Release'
```

Сборщик проверяет состав и SHA‑256 файлов. Файлы с именем уже готового
выпуска сохраняются в первоначальном виде.
