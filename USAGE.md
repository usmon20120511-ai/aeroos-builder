# Инструкция по сборке

## 0. Подготовка (один раз)

1. Установи **Windows ADK → Deployment Tools**. Нужен только `oscdimg.exe`.
   Официальная страница: https://learn.microsoft.com/windows-hardware/get-started/adk-install
   Проверить можно командой:
   ```powershell
   Test-Path 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
   ```
2. Скачай **официальный ISO Windows 11 Pro ru-ru x64** с сайта Microsoft.
   Это единственный бинарный файл, который тебе понадобится. Сборщик его не содержит.
3. Открой PowerShell **от имени администратора**.

## 1. Сборка по умолчанию

```powershell
cd "$env:USERPROFILE\Desktop\aeroOS-Builder"
powershell -ExecutionPolicy Bypass -File .\scripts\Build-AeroOS.ps1 `
  -SourceIso 'C:\ISO\Windows11_Pro_ru-ru_x64.iso'
```

Что произойдёт:

1. ISO монтируется, его содержимое копируется в рабочую папку (загрузчики и `setup.exe` остаются родными, подпись не трогается)
2. Из `install.wim` берется только издание Pro и монтируется офлайн
3. Применяется рецепт `recipes/aeroos-public.json`
4. С официальных сайтов скачиваются установщики, проверяются хэши, кладутся в образ
5. WIM экспортируется обратно, правится `autorun.inf` и BCD, собирается ISO
6. Готовый ISO монтируется и проверяется, выводится его SHA256

Время: 10–25 минут в зависимости от диска. Место: 25–35 ГБ.

## 2. Параметры

| Параметр | По умолчанию | Зачем |
| --- | --- | --- |
| `-SourceIso` | обязательно | путь к официальному ISO |
| `-OutputIso` | Рабочий стол, `aeroOS-<сборка>.iso` | куда положить результат |
| `-WorkDir` | `%TEMP%\aeroos-build-<время>` | временные файлы (можно оставить для отладки) |
| `-EditionIndex` | авто: Pro, ru-RU | индекс издания в WIM |
| `-Recipe` | `recipes/aeroos-public.json` | что удалять и какие ключи писать |
| `-AppsConfig` | `config/apps.json` | список официальных ссылок |
| `-AppsCache` | нет | папка с уже скачанными установщиками (экономия трафика) |
| `-DriverFolder` | **нет** | папка со своими драйверами. По умолчанию не внедряется ничего |
| `-Wallpaper` | нет | своё изображение обоев (только то, что тебе принадлежит) |
| `-IntroVideo` / `-IntroPhoto` | нет | видео и фото для показа при входе. **Только для личного пользования** |
| `-NoExplorerPatcher` | выключен | не включать ExplorerPatcher (он без подписи) |
| `-SkipApps` | выключен | вообще не встраивать установщики приложений |

## 3. Примеры

### Уже скачивал установщики — не качивай снова

```powershell
.\scripts\Build-AeroOS.ps1 -SourceIso 'C:\ISO\win11.iso' `
  -AppsCache 'C:\AppsCache'
```

### Внедрить свои драйвера (например, для своего ноута)

```powershell
.\scripts\Build-AeroOS.ps1 -SourceIso 'C:\ISO\win11.iso' `
  -DriverFolder 'C:\MyDrivers'
```

### Личная версия с видео при входе

```powershell
.\scripts\Build-AeroOS.ps1 -SourceIso 'C:\ISO\win11.iso' `
  -IntroVideo 'C:\Media\my-clip.mp4' `
  -IntroPhoto 'C:\Media\my-photo.jpg'
```

Такую версию **нельзя** выкладывать публично — она содержит твои файлы.

## 4. Что НЕ происходит с текущей Windows

Скрипты работают только с файлом ISO и смонтированным WIM. Они не меняют:

- службы, реестр, обои, имя компьютера и всё остальное на твоём диске C:;
- `C:\Windows\Setup\Scripts`;
- состояние поиска (`WSearch`), Defender и т.д.

Если по какой-то причине сборка прервалась, напиши в issue лог из `%TEMP%\aeroos-build-*\logs`. Смонтированный образ будет автоматически отмонтирован без сохранения.

## 5. Проверка результата

После сборки в консоли будет строка `ISO_SHA256=...`. Проверь её сам:

```powershell
Get-FileHash "$env:USERPROFILE\Desktop\aeroOS-....iso" -Algorithm SHA256
```

Сборщик уже проверил внутри: наличие `setup.exe`, `boot\etfsboot.com`,
`efi\microsoft\boot\efisys.bin`, `sources\install.wim`, имя образа `aeroOS`.

**Обязательно сначала запусти ISO в виртуальной машине.** Только потом пиши на флешку.

## 6. Запись на флешку

ISO больше 4 ГБ — FAT32 не подойдёт. В Rufus:

- Partition scheme: **GPT**
- Target system: **UEFI (non-CSM)**
- File system: **NTFS**

## 7. Частые проблемы

**`oscdimg.exe not found`** — доустанови ADK → Deployment Tools (см. п. 0).

**`Access is denied` при `reg unload`** — скрипт сам повторяет выгрузку 6 раз. Если не помогло, закрой все окна с `regedit` и `dism`, удали папку монтирования вручную и запусти сборку заново.

**ExplorerPatcher не подходит для твоей сборки** — он привязан к конкретным билдам Windows. Используй `-NoExplorerPatcher`, если панель ведёт себя странно.

**После обновления Windows сбросились настройки** — feature update восстанавливает Defender/Edge и ломает ExplorerPatcher. Если это важно, не ставь крупные обновления на эту сборку.

## 8. Что можно выложить

Эту папку целиком: скрипты, рецепты, README. Нельзя выкладывать ISO/WIM, который получился на выходе. Формулировки и причины — в [NOTICE.md](NOTICE.md).
