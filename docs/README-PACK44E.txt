AwgChain - ПАК 44e (та же болячка на втором звене)
=================================================

ГДЕ МЫ
------
Пак 44d сработал: имя пары снова warpam, бат цел, конфиг звена 1
(warpam-hop1.conf) записан.

Но упало на втором конфиге:
  Access to the path '...\Configurations\warpam.conf' is denied.
Причина та же, что и в паке 44b: менеджер хранит каждый конфиг
со своим жёстким списком доступа (владелец SYSTEM, наследование
отключено, у админов только Delete). Патч 44b починил только
make-hop1-conf.ps1, а make-hop2-conf.ps1 остался старым. Мой промах.

ФАЙЛЫ
-----
patch-hop2conf-p44e.ps1  вшивает в make-hop2-conf.ps1 тот же Write-Conf:
                         снять атрибуты -> взять владение -> удалить ->
                         записать заново. Есть -Revert, бэкап .orig-p44e.
p44e-writeconf.ps1.txt   тело функции Write-Conf (отдельным файлом, чтобы
                         не мучиться с кавычками внутри патча).
fix-conf.ps1             универсальный вариант fix-hop1conf: показывает права
                         и сносит любой застрявший конфиг (и -hop1, и
                         основной), есть -All.
README-PACK44E.txt       этот файл

УСТАНОВКА (консоль от админа, строго по одной команде)
---------------------------------------------------------
Распаковать все файлы в C:\vpn.

1) Убрать с дороги старые защищённые конфиги (сначала без -Apply,
   чтобы видеть права):

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-conf.ps1 -Name warpam

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\fix-conf.ps1 -Name warpam -Apply

2) Залечить сам скрипт второго звена, чтобы проблема не вернулась:

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-hop2conf-p44e.ps1 -Script C:\vpn\make-hop2-conf.ps1

3) Поднять цепочку:

  awgchain.bat up

4) Проверить остановку охраны без taskkill (последнее непроверенное
   из пака 44a, жду GUARD=STOPSIGNALED без "killing it"):

  awgchain.bat ks off

5) Если чисто - стресс и выкладка исходников:

  awgchain.bat up

  awgchain.bat stress 10

  awgchain-git.bat push

ПОЧЕМУ ЭТО ЛЕЧЕНИЕ ВРЕМЕННОЕ
-------------------------------
Правильно вообще не писать конфиги из PowerShell в защищённую папку
менеджера. В паке 45 оба конфига будет создавать сам менеджер через
IPC: исчезнут и отказы в доступе, и ключи в простом тексте (DPAPI),
и требование запускать up от админа.

ОТКАТ ПАКА 44e
---------------
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-hop2conf-p44e.ps1 -Script C:\vpn\make-hop2-conf.ps1 -Revert
