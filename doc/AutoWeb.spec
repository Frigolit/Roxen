AutoWeb - utkast till specf�rslag (beh�ver lite mer detaljer)

S�h�r kan det se ut:

  +----------------------------------------------------------------+
  |RoXen                               F�retag: Linux Allehanda AB |         
  |                                                                |
  | /Mallverktyg\   /HTML-editor\  /Statistik\ /Hj�lp\             |
  |                                                                |
  |       [Vald vy]                                                |
  /                                                                /
        ...                                                        
  /                                                                /
  |                                                                |
  +----------------------------------------------------------------+


De olika vyerna:

   Mallverktyg:
   ------------

   � Koncept: man v�ljer en huvudtemplate, samt en navigationtemplate.
     Man kan sedan �ndra ett antal parametrar (f�rger, typsnitt, bilder etc.)
   � I templaten m�rks parametrarna upp med "$$parameternamn$$" eller dylikt.
   � Till templaten h�r en templatebeskrivningsfil:
       <variable name="bgcolor" type="color" title="Background color">
          [hj�lptext]
       </variable>
       <variable name="fgcolor" type="color" title="Foreground color">
          [hj�lptext]
       </variable>
       ....

       Med hj�lp av denna fil produceras ett antal wizards, antingen genom
       att skriva en pike-fil till disk eller dynamiskt leka med funktionspekare
       p� n�got jobbigt s�tt i en wizard.
   � Man vill nog �ven kunna �ndra varje parameter f�r sig, utan att stega
     igenom den stora wizarden. Till exempel lista varje parameter, med en l�nk
     till en ensides-wizard.



   HTML-editor:
   ------------

   � V�ldigt lik filv�ljaren i SiteBuilder (manager/tabs/10:files/page.pike).
     (En fillistning, med ett par knappar under. Zoomar man in p� en fil
      dyker ett g�ng andra knappar upp, till exempel radera fill/editera fil etc.)
   � Oklart om man ska till�ta underbibliotek...
   � Knappar i filsurfningsl�ge:
     � Skapa ny fil
     � Ladda upp fil
   � Knappar i inzoomat l�ge (p� fil):
     � Visa
     � Editera
     � Editera metadata
     � Ladda ner filen
     � Ladda upp filen
     � Radera filen
     � L�gg till i menyn/tag bort fr�n menyn
   � Menyeditor (bara f�r att �ndra ordningen p� knapparna)


   Statistik:
   ----------
   � Man f�r se en f�rdigkomponerad rapport, med n�gra vackra diagram etc.
     

   Hj�lp:
   ------

   En liten hj�lpsida kan kanske beh�vas...