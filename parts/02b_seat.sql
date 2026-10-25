-- =====================================================================================
--  PART 2b : STANDALONE SEAT POPULATION (OPTIONAL / IDEMPOTENT)
--  Populates SEAT table from COACH x COACH_CLASS (seat_id = coach_id*100 + seat_no)
--  Berth pattern: SL/3A bay of 8, 2A bay of 6, 1A lower/upper, chair cars window/middle/aisle
--  Safe to execute standalone or as part of full setup (idempotent WHERE NOT EXISTS)
-- =====================================================================================
INSERT INTO seat (seat_id, coach_id, seat_no, berth_type)
SELECT c.coach_id * 100 + n.lvl, c.coach_id, n.lvl,
       CASE
         WHEN c.class_code IN ('SL','3A') THEN
              DECODE(MOD(n.lvl, 8), 1,'LOWER', 2,'MIDDLE', 3,'UPPER', 4,'LOWER', 5,'MIDDLE', 6,'UPPER', 7,'SIDE LOWER', 'SIDE UPPER')
         WHEN c.class_code = '2A' THEN
              DECODE(MOD(n.lvl, 6), 1,'LOWER', 2,'UPPER', 3,'LOWER', 4,'UPPER', 5,'SIDE LOWER', 'SIDE UPPER')
         WHEN c.class_code = '1A' THEN DECODE(MOD(n.lvl, 2), 1, 'LOWER', 'UPPER')
         WHEN c.class_code = 'EC' THEN DECODE(MOD(n.lvl, 2), 1, 'WINDOW', 'AISLE')
         ELSE DECODE(MOD(n.lvl, 3), 1, 'WINDOW', 2, 'MIDDLE SEAT', 'AISLE')
       END
FROM   coach c
       JOIN coach_class cc ON cc.class_code = c.class_code
       JOIN (SELECT LEVEL AS lvl FROM dual CONNECT BY LEVEL <= 100) n ON n.lvl <= cc.seats_per_coach
WHERE  NOT EXISTS (
       SELECT 1 FROM seat s WHERE s.seat_id = c.coach_id * 100 + n.lvl
);

COMMIT;
