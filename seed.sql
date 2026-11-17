-- =========================================================
--  Datos iniciales: productos del Excel del 3 de julio 2024
--  (stock = inventario final de ese día). Ejecutar DESPUÉS de schema.sql.
-- =========================================================
insert into public.productos (id, nombre, cat, precio, stock, orden) values
  ('aguila-original','Águila Original','Cervezas',3500,28,0),
  ('aguila-light','Águila Light','Cervezas',0,27,1),
  ('pilsen','Pilsen','Cervezas',0,26,2),
  ('poker','Poker','Cervezas',0,27,3),
  ('club-colombia','Club Colombia','Cervezas',0,26,4),
  ('corona','Corona','Cervezas',10000,22,5),
  ('stella','Stella Artois','Cervezas',0,24,6),
  ('corona-tropical','Corona Tropical','Cervezas',0,0,7),
  ('3-cordilleras','3 Cordilleras','Cervezas',0,12,8),
  ('cola-y-pola','Cola y Pola','Cervezas',0,9,9),
  ('smirnoff','Smirnoff','Licores',0,4,10),
  ('mojito','Mojito','Licores',0,2,11),
  ('cuba-libre','Cuba Libre','Licores',0,2,12),
  ('aguardiente','Aguardiente','Licores',0,2,13),
  ('ron','Ron','Licores',0,1,14),
  ('whisky','Whisky','Licores',0,0,15),
  ('shot-aguardiente','Shot Aguardiente','Shots',0,0,16),
  ('shot-ron','Shot Ron','Shots',0,0,17),
  ('shot-whisky','Shot Whisky','Shots',0,0,18),
  ('gatorade','Gatorade','Sin alcohol',5000,6,19),
  ('coca-cola','Coca-Cola','Sin alcohol',0,10,20),
  ('coca-cola-zero','Coca-Cola Zero','Sin alcohol',0,11,21),
  ('agua','Agua','Sin alcohol',4000,16,22),
  ('weed-cbd','Weed CBD','Otros',0,24,23),
  ('weed-thc','Weed THC','Otros',0,21,24),
  ('weed-thc-roja','Weed THC Roja','Otros',0,1,25),
  ('dragon','Dragón','Otros',0,1,26),
  ('michelada','Michelada','Otros',0,150,27),
  ('vasos-10','Vasos 10','Insumos',0,0,28),
  ('vasos-12','Vasos 12','Insumos',0,0,29)
on conflict (id) do nothing;

-- Ejemplo: ventas y gasto del 3 de julio 2024 (igual al Excel). Puedes borrarlas.
insert into public.movimientos (tipo, fecha, ts, items, total, metodo) values
  ('venta','2024-07-03','2024-07-03 12:00-05','[{"pid":"aguila-original","nombre":"Águila Original","cant":2,"precio":3500}]',7000,'efectivo'),
  ('venta','2024-07-03','2024-07-03 13:00-05','[{"pid":"corona","nombre":"Corona","cant":1,"precio":10000}]',10000,'efectivo'),
  ('venta','2024-07-03','2024-07-03 14:00-05','[{"pid":"gatorade","nombre":"Gatorade","cant":1,"precio":5000}]',5000,'efectivo'),
  ('venta','2024-07-03','2024-07-03 14:30-05','[{"pid":"agua","nombre":"Agua","cant":2,"precio":4000}]',8000,'efectivo');
insert into public.movimientos (tipo, fecha, ts, descr, valor) values
  ('gasto','2024-07-03','2024-07-03 12:30-05','Almuerzo',14000);
