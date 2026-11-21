. (Join-Path $PSScriptRoot 'storage_codec.ps1')
function Write-AitJson([string]$Path, $Value) {
    $Value=Convert-AitStorageJson $Path $Value $true
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 16 -Compress), [Text.UTF8Encoding]::new($false))
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporary,$Path,($Path+'.bak'),$true) }
        else { [IO.File]::Move($temporary,$Path) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Read-AitJson([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    $stream=$null;$reader=$null
    try {
        $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
        if($stream.Length -gt 1048576){throw 'AIT2-100: oversized state file.'}
        $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$true)
        $value=$reader.ReadToEnd() | ConvertFrom-Json
        return Convert-AitStorageJson $Path $value $false
    } finally {if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
}
function Protect-AitMessage([string]$Text) {
    if ($env:HF_TOKEN) { $Text=$Text.Replace($env:HF_TOKEN,'[TOKEN REDACTED]') }
    $Text=[regex]::Replace($Text, '(?i)hf_[A-Za-z0-9_]{4,}', '[TOKEN REDACTED]')
    $Text=[regex]::Replace($Text, '(?i)(Bearer\s+)[^\s"<>]+', '$1[REDACTED]')
    return [regex]::Replace($Text, '(https?://[^\s?"<>]+)\?[^\s"<>]+', '$1?[QUERY REDACTED]')
}
function Assert-AitNotCancelled {
    if ($env:AIT2_CANCEL -and (Test-Path -LiteralPath $env:AIT2_CANCEL)) { throw 'AIT2-CANCELLED' }
}
function Write-AitEvent([string]$Stage, [string]$Message, [long]$Bytes = -1, [long]$Total = -1, [double]$Rate = 0) {
    Assert-AitNotCancelled
    if (-not $env:AIT2_STATUS) { return }
    if ($Stage) { $script:AitStage = $Stage }
    if ($Message) { $script:AitMessage = Protect-AitMessage $Message }
    Write-AitJson $env:AIT2_STATUS @{
        schema=1; job_id=$env:AIT2_JOB_ID; state='running'; stage=$script:AitStage
        message=$script:AitMessage; bytes=$Bytes; total=$Total; rate=$Rate; pid=$PID
        updated=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
}
function Read-AitLogTail([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {return ''}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        [void]$stream.Seek([Math]::Max(0,$stream.Length-8192),[IO.SeekOrigin]::Begin)
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
        try {return (Protect-AitMessage $reader.ReadToEnd())} finally {$reader.Dispose()}
    } finally {$stream.Dispose()}
}
function Get-AitDiagnostic([string]$Text,[string]$Code,[string]$Stage,[Exception]$Exception) {
    if ($Exception -and -not $Text) {$Text=$Exception.ToString()}
    $detail=Protect-AitMessage $Text
    if (-not $Code) { $Code=[regex]::Match($detail,'\b(?:AIT2|AIT|MUS)-(?:[0-9]+|CANCELLED)\b').Value }
    if (-not $Code) { $Code='AIT2-200' }
    if ($detail -match 'AIT2-CANCELLED') {$Code='AIT2-CANCELLED'}
    $source=$Code
    # .NET transport status is stable across Windows languages; message text is not.
    if ($Exception -and $Code -eq 'AIT2-200') {
        $current=$Exception;$webStatus='';$authenticationFailure=$false
        for ($depth=0;$current -and $depth -lt 16;$depth++) {
            if (-not $webStatus -and $current -is [Net.WebException]) {$webStatus=$current.Status.ToString()}
            if ($current -is [Security.Authentication.AuthenticationException]) {$authenticationFailure=$true}
            $current=$current.InnerException
        }
        $transportCode=switch ($webStatus) {
            'TrustFailure' {'AIT2-210'}
            'SecureChannelFailure' {'AIT2-222'}
            'Timeout' {'AIT2-211'}
            'NameResolutionFailure' {'AIT2-212'}
            'ProxyNameResolutionFailure' {'AIT2-212'}
            {$_ -in @('ConnectFailure','ConnectionClosed','SendFailure','ReceiveFailure','KeepAliveFailure','PipelineFailure')} {'AIT2-213'}
        }
        if ($authenticationFailure -and $transportCode -ne 'AIT2-210') {$transportCode='AIT2-222'}
        if ($transportCode) {$Code=$transportCode}
    }
    # Explicit auth/server/file errors are not reclassified from ambiguous words.
    if ($Code -notin @('MUS-130','MUS-132','MUS-133','MUS-134','MUS-135','MUS-260','MUS-261','MUS-262','MUS-263','MUS-264','MUS-265','MUS-281','AIT2-CANCELLED','AIT2-110','AIT2-111','AIT2-112','AIT2-120','AIT2-210','AIT2-211','AIT2-212','AIT2-213','AIT2-222')) {
        if ($detail -match '(?i)no space left|not enough (?:disk )?space|insufficient (?:disk )?space|disk is full|WinError 112|0x80070070|failed \(Storage\)|недостаточно места') { $Code='AIT2-214' }
        elseif ($detail -match '(?i)SHA-256 mismatch|hash mismatch|HashMismatch|failed \(Integrity\)') {$Code='AIT2-120'}
        elseif ($detail -match '(?i)ResolutionImpossible|No solution found|No matching distribution|failed \(Resolution\)') {$Code='AIT2-220'}
        elseif ($detail -match '(?i)CUDA out of memory|MemoryError|std::bad_alloc|not enough (?:memory|RAM)') {$Code='AIT2-221'}
        elseif ($detail -match '(?i)UnknownIssuer|CERTIFICATE_VERIFY_FAILED|certificate verify|invalid peer certificate|TrustFailure|trust relationship.*SSL|SSL certificate|certificate chain|сертификат.*недовер') { $Code='AIT2-210' }
        elseif ($detail -match '(?i)SSLError|SSLEOFError|SSL handshake|TLS handshake|TLSProtocol|handshakefailure|AuthenticationException') {$Code='AIT2-222'}
        elseif ($detail -match '(?i)NameResolution|name resolution|No such host|remote name could not be resolved|host is unknown|не удалось разрешить удаленное имя') { $Code='AIT2-212' }
        elseif ($detail -match '(?i)ProxyAuthentication|HTTP 407|proxy.*authentication') { $Code='AIT2-216' }
        elseif ($detail -match '(?i)UnauthorizedAccess|Access to the path.*denied|PermissionError|WinError 5\b|0x80070005|доступ к пути.*запрещен') { $Code='AIT2-215' }
        elseif ($detail -match '(?i)timed? out|timeout|TaskCanceled|OperationCanceled|exceeded.*limit|истекло время|время ожидания') { $Code='AIT2-211' }
        elseif ($detail -match '(?i)ConnectFailure|ConnectionError|ConnectError|connection (?:reset|refused|closed)|WinError 100|Unable to connect|Failed to fetch|error sending request|не удается соединиться') { $Code='AIT2-213' }
    }
    $catalog=@{
        'AIT2-111'=@('Не удалось проверить путь','Проверьте доступ к указанному пути из текущего аккаунта Windows и повторите. Если ошибка повторяется, сохраните ZIP-отчёт. Не создавайте и не удаляйте AppData вручную; модели и токен менять не нужно.','path_access',1)
        'AIT2-112'=@('Не удалось подготовить папку компонентов','Сохраните ZIP-отчёт с указанным путём. Существующие файлы не удаляйте: установщик сохраняет их и использует отдельный подкаталог. Если содержимое менялось во время установки, повторите операцию. Токен менять не нужно.','path',1)
        'MUS-130'=@('Неверный формат токена','Используйте личный Read Token со страницы https://huggingface.co/settings/tokens. Скопируйте целиком: hf_ и латинские буквы/цифры.','token',3)
        'MUS-140'=@('Некорректный путь установки','Выберите папку данных для компонентов и ресурсную папку нужного REAPER с reaper.ini; папка программы не всегда является ресурсной.','path',1)
        'MUS-170'=@('Установка запущена из другого аккаунта Windows','Запустите установку из того же аккаунта, в котором работает REAPER. Иначе файлы и настройки окажутся в другом профиле.','user',1)
        'AIT-410'=@('Не пройдена проверка Windows или свободного места','Нужна Windows x64. Проверьте свободное место на диске компонентов и технические сведения ниже.','platform',1)
        'MUS-132'=@('Токен не получен из интерфейса','Откройте окно компонентов, вставьте токен заново и повторите. Если помощник был остановлен антивирусом, проверьте его журнал.','local',3)
        'MUS-133'=@('Не удалось прочитать сохранённый токен','Нажмите «Заменить токен» и вставьте личный токен заново. Защищённое хранилище связано с профилем Windows; копирование на другой компьютер может не работать.','credential',3)
        'MUS-134'=@('Не удалось сохранить токен','Прежний сохранённый токен не заменён. Проверьте права записи либо снимите «Запомнить для установки других моделей» и повторите проверку.','credential',3)
        'MUS-135'=@('Не удалось удалить токен','Проверьте права записи в папку состояния приложения и повторите удаление. Токен не включайте в отчёт об ошибке.','credential',3)
        'MUS-260'=@('Hugging Face не разрешил доступ к модели','Проверьте токен, его права чтения и условия выбранной модели в том же аккаунте. HTTP 401/403 сам по себе не доказывает единственную причину.','access',3)
        'MUS-262'=@('Hugging Face отклонил авторизацию (401)','Токен мог быть скопирован не полностью, отозван или не иметь доступа к закрытой модели. Проверьте токен и аккаунт на сайте; не публикуйте токен в переписке.','access',3)
        'MUS-263'=@('Нет разрешения на модель (403)','Откройте страницу указанной модели в аккаунте владельца токена, примите условия и дождитесь доступа. Для fine-grained токена разрешите чтение этой gated-модели. Причиной также может быть отозванный доступ.','access',3)
        'MUS-261'=@('Hugging Face временно ограничил запросы (429)','Это не признак неправильного токена. Подождите указанное сервером время и повторите проверку. Не запускайте несколько установок одновременно.','rate_limit',3)
        'MUS-264'=@('Файл модели не найден на Hugging Face (404)','Проверьте доступ в браузере. Если доступ есть, модель или структура репозитория могла измениться: нужен актуальный скрипт. Не скачивайте веса из случайных источников.','remote',3)
        'MUS-265'=@('Временная ошибка сервера Hugging Face (5xx)','Повторите позже. Замена токена или переустановка Python такую ошибку обычно не исправляет.','server',3)
        'MUS-266'=@('Сервер вернул неожиданный ответ','Проверьте, открывается ли Hugging Face без страницы входа провайдера/прокси. Сохраните отчёт; токен повторно не создавайте только из-за этого сообщения.','remote',3)
        'AIT2-210'=@('Не пройдена проверка HTTPS-сертификата','Проверьте дату/время Windows, обновления корневых сертификатов и HTTPS-фильтрацию антивируса/корпоративного прокси. Не отключайте проверку TLS. При необходимости обратитесь к администратору сети.','tls',3)
        'AIT2-211'=@('Сервер не ответил вовремя или загрузка зависла','Проверьте доступ к указанному источнику и повторите. Если соединение обрывается только в этой сети, попробуйте другую доверенную сеть. Токен менять не требуется.','timeout',3)
        'AIT2-212'=@('Не удалось определить адрес сервера (DNS)','Проверьте подключение и DNS-настройки Windows/роутера. Убедитесь, что сайт источника открывается в браузере.','dns',3)
        'AIT2-213'=@('Не удалось установить соединение или оно оборвалось','Повторите проверку после восстановления связи. При проверке доступа это не ответ об отказе в авторизации: менять токен и переустанавливать рабочие модели не нужно. Проверьте интернет, прокси и журнал защитного ПО; не отключайте проверку HTTPS или антивирус целиком.','network',3)
        'AIT2-214'=@('Недостаточно места на диске','Освободите место на диске папки компонентов, затем повторите. Large требует дополнительно места для весов и рабочего окружения; размер весов не равен общему размеру установки.','storage',1)
        'AIT2-215'=@('Windows запретила запись или запуск файла','Выберите доступную папку данных вне Program Files и проверьте права, Controlled Folder Access и журнал антивируса. Не запускайте установку от другого пользователя.','permissions',1)
        'AIT2-216'=@('Прокси требует авторизацию (407)','Настройте системный прокси Windows или обратитесь к администратору сети. Hugging Face-токен не является паролем прокси.','proxy',3)
        'AIT2-220'=@('Конфликт версий Python-пакетов','Сеть и токен здесь могут быть исправны. Создайте новое окружение из актуального установщика. Если конфликт повторяется, отправьте отчёт; не меняйте версии пакетов наугад.','dependencies',1)
        'AIT2-221'=@('Не хватило оперативной или видеопамяти','Закройте приложения, использующие память, и попробуйте small или CPU. Проверьте файл подкачки Windows. Скачивать исправные веса заново не нужно.','memory',2)
        'AIT2-222'=@('Ошибка защищённого соединения TLS','Соединение TLS оборвалось или согласование протокола не удалось. Это не обязательно ошибка сертификата. Проверьте сеть, системный прокси и HTTPS-фильтрацию; не отключайте проверку TLS.','tls_protocol',3)
        'AIT2-110'=@('Неподходящий путь компонентов','Выберите обычную доступную папку, не корень диска, системную папку целиком, файл или junction. Папка может быть непустой: существующие файлы сохраняются, для компонентов используется отдельный подкаталог.','path',1)
        'AIT2-120'=@('Повреждён или изменён файл установки','Повторно распакуйте официальный ZIP в отдельную папку. Проверьте журнал защитного ПО. Контрольная сумма не обходится.','integrity',1)
        'AIT2-130'=@('Другая установка уже работает','Дождитесь её завершения. Не удаляйте lock-файлы и не запускайте второй установщик параллельно.','busy',0)
        'AIT2-150'=@('Фоновый помощник был прерван','Прежняя активная конфигурация сохранена. Откройте журнал и повторите после устранения причины остановки.','interrupted',1)
        'AIT2-160'=@('Не удалось безопасно продолжить незавершённое окружение','Служебная запись или принадлежность папки не прошла проверку. Ничего не удалено. Скопируйте отчёт для поддержки; не удаляйте действующее окружение вручную.','runtime_record',1)
        'AIT2-CANCELLED'=@('Операция остановлена пользователем','Прежняя активная конфигурация сохранена. Для продолжения запустите установку снова.','cancelled',1)
        'MUS-210'=@('Не удалось подготовить UV','Проверьте доступ к GitHub и журнал загрузки. При ошибке SHA-256 повторно распакуйте проверенный архив; не обходите проверку.','runtime',1)
        'MUS-220'=@('Не удалось установить Python для MuScriptor','Все способы подготовки Python не дали рабочего окружения. Подробная причина последней попытки — ниже и в журнале; проверьте сеть, права и наличие tar.exe в Windows.','python',1)
        'AIT-440'=@('Не удалось установить Python для Basic Pitch','Проверьте подробности загрузки/распаковки Python. Работающий MuScriptor не удаляется.','python',1)
        'MUS-230'=@('Не удалось создать Python-окружение','Проверьте права и свободное место в папке компонентов. Не перемещайте готовый venv; при ремонте создайте новое окружение.','environment',1)
        'AIT-450'=@('Не удалось создать окружение Basic Pitch','Проверьте папку данных и права записи. MuScriptor может работать без Basic Pitch.','environment',1)
        'MUS-240'=@('Не установлены зависимости MuScriptor','Посмотрите техническую причину и журнал: конфликт пакетов, сеть и повреждённый файл требуют разных действий. Не удаляйте рабочие веса.','dependencies',1)
        'MUS-241'=@('Ошибка сертификата при загрузке пакетов MuScriptor','Проверьте сертификаты Windows, дату и HTTPS-фильтрацию сети; проверку TLS не отключайте.','tls',3)
        'MUS-242'=@('Сбой сети при загрузке пакетов MuScriptor','Повторите после восстановления доступа к PyPI и download.pytorch.org. Токен Hugging Face к этим источникам не относится.','network',3)
        'AIT-460'=@('Не установлены зависимости Basic Pitch','Проверьте технические подробности и журнал установки Basic Pitch.','dependencies',1)
        'AIT-461'=@('Ошибка сертификата при загрузке Basic Pitch','Проверьте время и сертификаты Windows, прокси и HTTPS-фильтрацию. Не отключайте проверку TLS.','tls',1)
        'AIT-462'=@('Сбой сети при загрузке Basic Pitch','Повторите установку дополнения после восстановления доступа к PyPI.','network',1)
        'MUS-250'=@('Окружение MuScriptor не прошло проверку','Проверьте подробности CUDA/CPU и драйвер NVIDIA. Для переустановки откройте Компоненты и модели → Восстановление → Переустановить компоненты. Прежнее окружение сохраняется.','validation',0)
        'MUS-281'=@('Не удалось проверить локальные файлы модели','Выберите папку с целыми model.safetensors и config.json. Если готовых файлов ещё нет, нажмите «Установить с нуля». Проверьте доступность цели ссылки; скачивание автоматически не запускается.','model_integrity',9)
        'MUS-251'=@('Не работает обработка аудио Python','Не прошла проверка NumPy/SoundFile/libsndfile. Создайте новое окружение; FFmpeg для этого не нужен.','validation',1)
        'MUS-270'=@('Не удалось загрузить веса модели','Смотрите HTTP-код/сетевую причину ниже. Повторный запуск может продолжить загрузку; не включайте скачивание заново без необходимости.','weights',3)
        'MUS-280'=@('Модель не прошла локальную проверку','Возможны нехватка RAM/VRAM, повреждённые веса или несовместимое окружение. Подробности — в model_validation.log. Код сам по себе не доказывает повреждение файла.','validation',2)
        'MUS-290'=@('Не удалось подключить проверенные файлы','Проверьте права и наличие файлов в папке компонентов. Активная конфигурация переключается только после проверки.','integration',1)
        'AIT-470'=@('Basic Pitch не прошёл проверку запуска','Проверьте журнал TensorFlow/Python и технические сведения ниже.','validation',1)
        'AIT2-100'=@('Повреждены параметры задания','Повторите операцию из актуального интерфейса. Если ошибка повторяется, распакуйте официальный ZIP заново.','request',1)
        'MUS-110'=@('Не выбраны поддерживаемые модели','Выберите small, medium или large в помощнике.','request',2)
        'AIT2-310'=@('Не удалось просмотреть временные WAV и MIDI','Проверьте доступ к служебной папке Ai Transcriber и повторите. Модели и окружения не затрагиваются.','storage',8)
        'AIT2-311'=@('Список очистки устарел или изменился','Обновите список временных WAV и MIDI, выберите файлы и подтвердите очистку заново.','storage',8)
        'AIT2-320'=@('Не удалось создать ZIP-отчёт','Проверьте свободное место и доступ к папке состояния. Можно по-прежнему скопировать текст ошибки и открыть папку журнала.','report',0)
    }
    $entry=$catalog[$Code]
    if (-not $entry) { $entry=@('Установка не завершена','Сохраните отчёт и журнал задания. Не удаляйте работающие модели: по этому коду точную причину определить нельзя.','unknown',1) }
    if ($detail.Length -gt 2400) { $detail=$detail.Substring(0,1000)+"`n…`n"+$detail.Substring($detail.Length-1400) }
    $stages=@{starting='Проверка параметров';paths='Проверка папки компонентов';local_model='Проверка локальной модели';access='Проверка токена и доступа к моделям';token='Передача токена';uv='Подготовка UV';runtime='Установка Python, пакетов и моделей';checking='Проверка окружения';storage='Временные WAV и MIDI';report='Создание ZIP-отчёта'}
    if ($stages.ContainsKey([string]$Stage)) {$Stage=$stages[$Stage]}
    return @{code=$Code;source_code=$source;title=$entry[0];help=@($entry[1]);category=$entry[2];retry_page=$entry[3];stage=$Stage;detail=$detail}
}

function Assert-AitOrdinaryPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        try {
            $exists=Test-Path -LiteralPath $current -ErrorAction Stop
            $attributes=if($exists){(Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes}else{$null}
        } catch {
            throw [IO.IOException]::new(('AIT2-111: Не удалось проверить путь: '+$current+'. '+$_.Exception.Message),$_.Exception)
        }
        if ($exists -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "AIT2-110: Выберите обычную папку без junction/символических ссылок: $current"
        }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}
function Test-AitPayload([string]$Root) {
    $manifest=Read-AitJson (Join-Path $Root 'manifest.json')
    if (-not $manifest -or $manifest.version -ne '0.2.5' -or -not $manifest.files) { throw 'AIT2-120: Нет корректного манифеста. Повторно распакуйте установочный архив.' }
    foreach ($entry in $manifest.files.PSObject.Properties) {
        $path=[IO.Path]::GetFullPath((Join-Path $Root $entry.Name))
        if (-not $path.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'AIT2-120: Invalid manifest path.' }
        Assert-AitOrdinaryPath $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path).Hash -ne $entry.Value) {
            throw ('AIT2-120: Повреждён или изменён файл: '+$entry.Name)
        }
    }
}
