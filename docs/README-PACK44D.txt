AwgChain - ПАК 44d (исправление моей ошибки в паке 44c)
=====================================================

ЧТО Я СЛОМАЛ
-------------
Патч 44c добавил в awgchain.bat новые метки и переходы внутри :detectpair.
cmd.exe этого не переварил:
  =" :dpdefault set "PAIRSRC=the was unexpected at this time.
Правило на будущее: логика проверки - в PowerShell, в бате меняем
только отдельные строки, без новых меток и goto.

Плюс что уже сделано и работает: мусор убран (служба и два файла с
именем " ="), права на конфиги вылечены паком 44b.

ФАЙЛЫ
-----
detect-pair.ps1        v2: имя пары проверяется по ^[A-Za-z0-9_][A-Za-z0-9_-]{0,47}$,
                       мусор отбрасывается, если ничего нет - отдаёт warpam.
                       В stdout идёт только имя, есть режим -Explain.
patch-bat-p44d.ps1     минимальная правка бата: имя по умолчанию warpam
                       вместо hop2-amnezia и одна строка вывода пары в up.
                       Никаких меток и переходов не добавляет, в конце
                       проверяет, что остатков пака 44c в файле нет.
README-PACK44D.txt     этот файл

УСТАНОВКА (консоль от админа, строго по одной команде)
---------------------------------------------------------
Распаковать в C:\vpn с заменой (detect-pair.ps1 будет заменён на v2).

1) Откатить сломанный патч 44c - бат снова заработает:

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44c.ps1 -Bat C:\vpn\awgchain.bat -Revert

2) Проверить, что бат жив и какое имя даёт новый определитель:

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\detect-pair.ps1 -Explain

3) Минимальная правка бата:

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44d.ps1 -Bat C:\vpn\awgchain.bat

4) Поднять цепочку. В шапке должна быть строка
   "pair : warpam   hidden hop: warpam-hop1":

  awgchain.bat up

5) Главная непроверенная вещь из пака 44a - остановка охраны без taskkill:

  awgchain.bat ks off

   Жду GUARD=STOPSIGNALED без строки "guard still running, killing it".

6) Если чисто - стресс и выкладка:

  awgchain.bat up

  awgchain.bat stress 10

  awgchain-git.bat push

АВАРИЙНЫЙ ВАРИАНТ
-----------------
Если после пункта 1 бат всё равно ругается - восстанови его из бэкапа
вручную (в папке C:\vpn лежат awgchain.bat.orig-p44c и более ранние
.orig-* копии), или задай имя руками в том же окне:

  set AWGCHAIN_PAIR=warpam

  awgchain.bat up

ОТКАТ ПАКА 44d
---------------
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44d.ps1 -Bat C:\vpn\awgchain.bat -Revert

Бэкап: awgchain.bat.orig-p44d
