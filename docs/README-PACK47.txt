AwgChain, pack 47 - верхнее звено будит нижнее
=================================================

Главное по логам пака 46: патч 26 РАБОТАЕТ
--------------------------------------------
Раньше в отчёте стояло hop2_state=absent (служба умирала). Сейчас:

    1,FAIL,60,Stopped,Running,,the chain did not carry traffic within 60 seconds

Служба второго звена жива все 60 секунд и честно ждёт, в логе видно:

    Chain: pinned interface "warpam-hop1" not found, so we wait for it
    instead of shutting the tunnel down
    Chain pin route: ... so the route is pinned once the hop underneath is here
    Chain: the hop underneath never came up, the tunnel stays but carries nothing

Фатальная ошибка устранена. Осталась вторая половина задачи.

Что ещё не работает
--------------------
hop1_state=Stopped все десять циклов. Первое звено никто не запускал.
Стресс делает sc start только для службы второго звена - ровно так же
поступают автозапуск Windows и кнопка в окне. Порядок звеньев
(chainStartParents) живёт в менеджере и срабатывает только когда подъём идёт
через него. Поэтому цепочка и не поднималась без бата.

Что делает патч 28
-------------------
Файл tunnel\chainpinwait.go заменяется новой версией. Пока служба ждёт
свой пин-интерфейс, она каждые 10 секунд просит диспетчер служб Windows
запустить службу нижнего звена (AwgChainTunnel$warpam-hop1). Окно ожидания
увеличено с 60 до 90 секунд. Любая ошибка запуска только пишется в лог,
ожидание продолжается, так что подъём через бат или менеджер не ломается.

Возможный подвох (честно)
--------------------------
Служба туннеля сбрасывает привилегии после старта (в логе "Dropping
privileges"). Если урезанному токену не хватит прав на запуск чужой службы,
в логе появится строка вида

    Chain: could not start AwgChainTunnel$warpam-hop1: Access is denied.

Это не поломка, а ответ на вопрос: тогда в паке 48 запуск нижнего звена
сделаем из менеджера (он работает от SYSTEM и службы уже создаёт сам).
Поэтому пришли логи в любом случае - и при успехе, и при провале.

Состав пака
-----------
  patch28.ps1              замена tunnel\chainpinwait.go, бэкап .orig-p47
  p47-chainpinwait.go.txt  сам файл (класть в C:\vpn)
  README-PACK47.txt        этот файл

Порядок команд
--------------
  cd /d C:\vpn
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch28.ps1
  awgchain.bat build
  awgchain.bat install
  awgchain.bat up
  awgchain.bat stress 10
  awgchain-logs2.bat

up нужен чтобы службы цепочки существовали, стресс дальше проверяет подъём
без бата: он запускает только второе звено, первое должно подняться само.

Откат
-----
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch28.ps1 -Revert
