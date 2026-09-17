AwgChain - пак 52
Замок перевзводится после ремонта + честное предупреждение у команды up
=====================================================================

ЗАЧЕМ

Пак 51 перенёс замок (фильтры WFP) внутрь службы менеджера, и это
подтверждено журналом. Но в цикле ремонта осталась ложь:

  Repair: the chain is back up after N seconds,
  the kill switch follows the new interfaces by itself

Для фильтров внутри процесса это неверно. Каждое правило привязано к LUID
адаптера, который существовал в момент установки замка. Ремонт гасит оба
звена и поднимает их заново, Windows выдаёт новые адаптеры с новыми LUID
(в журнале индекс прыгал с 7 на 18). После ремонта замок сторожит уже
мёртвые интерфейсы.

Второе: awgchain.bat up поднимает цепочку мимо менеджера, а оба звена при
этом пишут "leaving the kill switch to the chain rule set" - свой замок не
ставят. Значит после up машина открыта, и об этом надо говорить вслух.

ЧТО В ПАКЕ

  patch33.ps1            - новый файл manager\chainrelock.go + одна строка
                           в manager\chainguard.go (ветка успеха ремонта)
  p52-chainrelock.go.txt - тело нового файла
  patch-bat-p52.ps1      - одна строка в awgchain.bat: up честно пишет,
                           что замка нет
  README-PACK52.txt      - этот файл

КАК РАБОТАЕТ

После каждого удачного ремонта менеджер снимает замок и ставит его заново
на те адаптеры, которые есть сейчас. Фильтры живут в одной динамической
сессии WFP, поэтому старый набор надо убрать до установки нового - окно
открытости несколько миллисекунд, это несравнимо лучше замка, указывающего
на мёртвые интерфейсы. Если адаптеры ещё не готовы, попытка повторяется
до 10 раз с паузой 2 секунды, и при полной неудаче в журнал идёт прямая
строка "the machine is open right now".

Команды по одной:

  copy /Y "%USERPROFILE%\Downloads\pack52\*" C:\vpn\

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch33.ps1

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p52.ps1

  awgchain.bat build

  awgchain.bat install

  awgchain.bat gui

Дальше в окне программы подними цепочку, дождись интернета и проверь
ремонт: в другом окне погаси нижнее звено и смотри журнал.

  sc stop AwgChainTunnel$warpam-hop1

Через минуту выгрузи журнал и пришли архив:

  awgchain.bat applog

  awgchain-logs2.bat

ЧТО ДОЛЖНО БЫТЬ В ЖУРНАЛЕ

  Repair: the chain is back up after N seconds, re-arming the kill switch
  on the new interfaces
  Repair: kill switch re-armed on the new interfaces on try 1

Строки "follows the new interfaces by itself" быть больше не должно.

ОТКАТ

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch33.ps1 -Revert

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p52.ps1 -Revert

Без пересборки замок внутри процесса целиком отключается файлом
C:\ProgramData\AwgChain\no-inproc-lock (возврат к отдельной охране).
