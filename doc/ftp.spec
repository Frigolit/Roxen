Some thoughts in Swedish:

Tv� protokoll http och ftp som skiljer sig p� n�gra punkter:

 - http anv�nder sig av en host-header f�r att v�lja kund.
 - ftp har ingen host header utan f�r l�gga information i
   inloggningsnamnet namn@domain eller namn*domain.

F�r att hantera anv�ndarkontroll f�r b�da protokollen skrivs l�mpligen
en auth-modul som kontrollerar anv�ndarnamn och s�tter r�tt kund.

Endast upload ska st�djas.
Vissa taggar ska tolkas och specialbehandlas.
 - titel       <title>Welcome</title>
 - keywords ur <meta name="keywords" content="Intruduction">
 - description <meta name="description"
                     content="Intruduction to the UltraViking Company">
 - template ur <template> ... </template>
TODO
  Kolla att metadatan extraheras korrekt.
  Fixa cache-reloadbuggen vid uppload.
  kolla om busiga filnamn strular.