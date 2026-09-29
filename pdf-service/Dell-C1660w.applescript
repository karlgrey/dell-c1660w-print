-- Droplet fuer das PDF-Menue des Druckdialogs (wird von install.sh mit
-- osacompile zu "An Dell C1660w senden.app" uebersetzt; @SERVICE@ wird ersetzt).
on run
	display dialog "Diese App wird aus dem PDF-Menue des Druckdialogs aufgerufen (Drucken > PDF > An Dell C1660w senden)." buttons {"OK"} default button "OK" with title "An Dell C1660w senden"
end run

on open theFiles
	repeat with f in theFiles
		set p to POSIX path of f
		try
			do shell script "DELLPRINT_NO_NOTIFY=1 '@SERVICE@' 'PDF' '' " & quoted form of p
			display notification "Der Druckauftrag wurde gesendet." with title "Dell C1660w"
		on error msg
			display notification msg with title "Dell C1660w - Fehler"
		end try
	end repeat
end open
