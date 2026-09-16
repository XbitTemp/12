AwgChain - ПАК 44c (имя пары туннелей)
====================================

ЧТО СЛУЧИЛОСЬ
-------------
Права мы вылечили - конфиги теперь записываются (в логе "wrote ...").
Но вылезла вторая поломка: имя пары туннелей стало " =" вместо "warpam".
Поэтому бат создал " =-hop1.conf" и " =.conf", а служба с таким именем
адаптер поднять не смогла:
  [FAIL] The  =-hop1 adapter never appeared

ПОЧЕМУ (по исходникам из твоего GitHub)
------------------------------------------
В awgchain.bat есть :detectpair, он спрашивает имя у detect-pair.ps1.
А detect-pair.ps1 берёт имя из двух мест: установленная служба
AwgChainTunnel$<имя>-hop1 или файл <имя>-hop1.conf в папке конфигов.
Мы удалили warpam-hop1.conf (иначе его было не перезаписать), служб тоже
не было - имя взять было неоткуда, и бат проглотил мусор без проверки.
То есть сама цепочка цела, сломалось только имя.

ФАЙЛЫ
-----
patch-bat-p44c.ps1    в :detectpair появляется проверка имени (только буквы,
                      цифры, дефис и подчёркивание), мусор отбрасывается,
                      имя по умолчанию - warpam, а up печатает пару и источник
                      имени - такую ошибку будет видно сразу
clean-badconfs.ps1    убирает мусор: службы и файлы с испорченными именами
README-PACK44C.txt    этот файл

УСТАНОВКА (консоль от админа, по одной команде)
-----------------------------------------------------
Распаковать в C:\vpn с заменой.

1) Убрать мусор (сначала посмотреть, что нашлось):

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\clean-badconfs.ps1

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\clean-badconfs.ps1 -Apply

2) Защитить бат от плохого имени:

  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44c.ps1 -Bat C:\vpn\awgchain.bat

3) Поднять цепочку. В шапке теперь будет строка "pair : warpam ...":

  awgchain.bat up

4) Главная проверка пака 44a - остановка охраны без taskkill:

  awgchain.bat ks off

   Жду GUARD=STOPSIGNALED без строки "guard still running, killing it".

5) Если всё чисто - стресс и выкладка:

  awgchain.bat up

  awgchain.bat stress 10

  awgchain-git.bat push

ЕСЛИ СРОЧНО НУЖНО БЕЗ ПАТЧА
---------------------------
В том же окне консоли имя можно задать руками:

  set AWGCHAIN_PAIR=warpam

  awgchain.bat up

ОТКАТ
-----
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch-bat-p44c.ps1 -Bat C:\vpn\awgchain.bat -Revert

Бэкап: awgchain.bat.orig-p44c
