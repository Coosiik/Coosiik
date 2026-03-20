# Coosiik Crafting VORP

Resource do RedM/VORP z rozbudowanym craftingiem i filmowym NUI inspirowanym menu z przeslanych screenow.

## Co dostajesz
- pełne NUI z ukladem lewy panel / srodek / prawy panel,
- osobny widok drzewka blueprintow z polaczeniami miedzy node'ami,
- punkty skilli i osobne punkty researchu do odblokowywania blueprintow,
- stanowiska pod survival, weapons i blacksmith,
- walidacje skladnikow oraz craftingu po stronie serwera.

## Sterowanie
- `J` przy stanowisku: otwarcie craftingu,
- `B` przy stanowisku: otwarcie drzewka blueprintow,
- `/blueprints`: otwarcie drzewka blueprintow z komendy,
- `ESC`: zamkniecie NUI.

## Architektura
- `fxmanifest.lua` - resource + definicja NUI,
- `config.lua` - stanowiska, kategorie, receptury i drzewko blueprintow,
- `client.lua` - fokus NUI, callbacki i obsluga stanowisk,
- `server.lua` - sprawdzanie inventory, skilli, researchu i nagrod,
- `web/index.html` - struktura interfejsu,
- `web/style.css` - styl zblizony do pokazanych screenow,
- `web/app.js` - logika widoku craftingu i blueprint tree.

## Jak dziala research
1. Crafting daje XP do konkretnej galezi.
2. Co 100 XP gracz dostaje:
   - punkty umiejetnosci,
   - punkty blueprintow.
3. Punkty umiejetnosci wydajesz na levele galezi.
4. Punkty blueprintow wydajesz w drzewku researchu.
5. Dopiero odblokowany blueprint pozwala craftowac dany item.

## Co trzeba jeszcze podpiac po twojej stronie
- prawdziwa nazwe inventory resource w `Config.InventoryApiResource` (np. `vorp_inventory` albo `vorp_inventoryApi`),
- prawdziwe itemy z twojego inventory (`iron`, `copper`, `hardwood`, itd.),
- docelowe nazwy itemow/rewardow dla twojego serwera,
- opcjonalnie podmiane ikon emoji na obrazy DDS/PNG w NUI,
- opcjonalnie zapis do bazy MySQL zamiast trzymania stanu w pamieci resource.
