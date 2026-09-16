ПАК 45 - служба туннеля ждёт звено под собой, а не умирает

ЧТО ЛЕЧИМ

В логах пака 44e стресс падал так:

  [TUN] [warpam] Startup complete
  [TUN] [warpam] Unable to bind sockets to default route: pinned interface "warpam-hop1" not found
  [TUN] [warpam] Chain pin route: pinned interface "warpam-hop1" not found
  [TUN] [warpam] Device closing

Служба второго звена считала отсутствие адаптера первого звена смертельной
ошибкой и гасла через 7 миллисекунд после старта. Цепочку потом собирал
ремонтный цикл менеджера за 5-20 секунд, в окно стресса это не укладывалось.
Это же объясняет "туннели не запускаются" в окне программы и попытку
переподключения при ручном выключении звена.

ЧТО ДЕЛАЕТ ПАК 45

1. pinendpoint.go: три условия (адаптера нет, адаптер ещё не поднят, нет
   индекса для этого семейства адресов) теперь помечаются как временные.
2. interfacewatcher.go: временная ошибка больше не уходит в канал фатальных
   ошибок. Вместо остановки службы запускается ожидание: каждые 2 секунды,
   до 60 секунд, проверяем адаптер и привязываем сокет, как только он есть.
3. pinroute.go: маршрут к эндпоинту тоже не теряется - он штифтуется, как
   только адаптер звена под нами появился.
4. Новый файл tunnel\chainpinwait.go - вся логика ожидания в одном месте.

Итог: службу второго звена можно запускать в любом порядке - автозапуском
Windows, кнопкой в окне, через sc start. Она дождётся первого звена сама.

ФАЙЛЫ ПАКА

  patch26.ps1              - патч (бэкапы .orig-p45, есть -Revert)
  p45-chainpinwait.go.txt  - новый файл tunnel\chainpinwait.go
  awgchain-tag.bat         - ставит тег на текущий коммит и шлёт его на GitHub
  README-PACK45.txt        - этот файл

КУДА КЛАСТЬ

Все четыре файла в C:\vpn (окно командной строки от администратора).

ПОРЯДОК ДЕЙСТВИЙ (по одной команде за раз)

  cd /d C:\vpn
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch26.ps1
  awgchain.bat build
  awgchain.bat install
  awgchain.bat up
  awgchain.bat stress 10

Ждём RESULT=OK у патча и прохождение стресса без падений.

ОТКАТ

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch26.ps1 -Revert

ПРО ТЕГИ ВМЕСТО ВЕТОК

Отдельная ветка на каждый push не нужна: работа линейная, ветки превратятся
в свалку. Пушим всегда в main, а на каждый применённый пак ставим тег:

  awgchain-git.bat push
  awgchain-tag.bat pack45

Вернуться к любому снимку потом можно так:

  git -C C:\vpn\repo checkout pack44e
