AwgChain - pack 51
Kill switch pereezzhaet iz otdelnogo processa v sluzhbu menedzhera

==========================================================
ZACHEM
==========================================================
Seychas zamok stavit awgchain-guard.exe. Iz-za etogo tri problemy:

1. Pri podyeme est okno bez zamka: zamok poyavlyaetsya tolko posle togo,
   kak menedzher zapustil otdelnyy process. V stress-teste zamka net voobshche.
2. Posle vykhoda iz programmy internet vozvrashchaetsya tolko cherez 2 minuty
   (-orphangrace 120): okhrana ne mozhet otlichit umyshlennyy vykhod ot avarii.
3. Radi etogo prikhoditsya derzhat sobytie ostanovki, schetchik smertey okhrany
   i flag -mgrpid.

Filtry WFP zhivut rovno stolko, skolko zhivet postavivshiy ikh process. Znachit
sluzhba menedzhera - pravilnoe mesto: esli menedzher upal, mashina otkryvaetsya
sama, a esli menedzher zhiv, on snimaet zamok srazu pri ostanovke tunnelya.

Otkat bez peresborki: sozdat fayl C:\ProgramData\AwgChain\no-inproc-lock -
menedzher vernetsya k staroy okhrane.

==========================================================
SHAGI
==========================================================

0) Raspakovat arkhiv v C:\vpn (fayly patch32.ps1 i p51-chainlock.go.txt
   dolzhny lezhat ryadom, v odnoy papke).

1) Patch:

   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch32.ps1

   Zhdem RESULT=OK i dve stroki [OK]: written chainlock.go i patched chainguard.go.

2) Sborka i ustanovka:

   awgchain.bat build
   awgchain.bat install

3) Podnyat tsepochku:

   awgchain.bat up

4) PROVERKA 1 - zamok stavit menedzher, a ne okhrana:

   tasklist | findstr /i awgchain-guard

   Pravilnyy otvet: nichego ne naydeno (process okhrany bolshe ne nuzhen).

   awgchain.bat applog

   V C:\vpn\logs\app-log.txt dolzhna byt stroka:
   Kill switch armed inside the manager ... no separate guard process

5) PROVERKA 2 - internet vozvrashchaetsya srazu, bez dvukh minut.
   Vyyti iz programmy (ili ostanovit tunnel v okne) i srazu zamerit:

   curl.exe -s --max-time 8 --no-keepalive https://api.ipify.org

   Pravilnyy otvet: adres provaydera poyavlyaetsya za neskolko sekund,
   a ne cherez 2 minuty. V zhurnale: Kill switch lifted, the machine is open again

6) PROVERKA 3 - staraya komanda vse eshche rabotaet:

   awgchain.bat ks off

   Zamok dolzhen snyatsya (v zhurnale: the kill switch was asked to stand down).

7) Stress:

   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\stress-chain.ps1 -Cycles 10 -Expect 104.253.25.108 -Settle 20 -UpTimeout 90

   Zhdem OK=10 FAIL=0 LEAK=0.

8) Logi v chat:

   awgchain-logs2.bat

==========================================================
ESLI CHTO-TO POSHLO NE TAK
==========================================================

Mashina bez interneta posle testa:

   awgchain.bat ks off
   sc stop AwgChainManager

(ostanovka sluzhby menedzhera garantirovanno snimaet zamok: sessiya WFP
dinamicheskaya i umiraet vmeste s processom)

Otkat patcha:

   powershell -NoProfile -ExecutionPolicy Bypass -File C:\vpn\patch32.ps1 -Revert
   awgchain.bat build
   awgchain.bat install

Otkat bez peresborki (vernut staruyu okhranu):

   echo. > C:\ProgramData\AwgChain\no-inproc-lock

==========================================================
POSLE USPEKHA
==========================================================

   awgchain-git.bat push
   awgchain-tag.bat pack51

I prishli svezhiy zip papki C:\vpn vmeste s repo - polozhu na stranitsu bekapov.
