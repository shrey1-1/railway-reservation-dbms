
-- =====================================================================================
--  PART 7 : VIEWS (derived information reused by the analysis and the risk module)
-- =====================================================================================
-- Metric definitions used everywhere:
--   capacity        = seats in all coaches of a train (per journey)
--   seats occupied  = tickets in status CONFIRMED / COMPLETED
--   occupancy %     = seats occupied / capacity * 100
--   cancellation %  = cancelled tickets / all tickets booked * 100
--   demand %        = (seats occupied + waitlisted) / capacity * 100   (unserved demand included)
--   revenue         = fares of travelled tickets + cancellation charges retained

-- VIEW 1 : RESERVATION PERFORMANCE - one row per journey (train + date)
CREATE OR REPLACE VIEW v_reservation_performance AS
SELECT s.schedule_id,
       t.train_no,
       t.train_name,
       t.route_id,
       s.journey_date,
       s.sched_status,
       cap.capacity,
       COUNT(r.pnr)                                                      AS total_bookings,
       COUNT(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN 1 END) AS seats_occupied,
       COUNT(CASE WHEN r.status = 'WAITLIST' THEN 1 END)                 AS waitlisted,
       COUNT(CASE WHEN r.status = 'CANCELLED' THEN 1 END)                AS cancelled,
       ROUND(100 * COUNT(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN 1 END) / cap.capacity, 2)
                                                                         AS occupancy_pct,
       ROUND(100 * COUNT(CASE WHEN r.status = 'CANCELLED' THEN 1 END) / NULLIF(COUNT(r.pnr), 0), 2)
                                                                         AS cancellation_rate,
       NVL(SUM(CASE WHEN r.status IN ('CONFIRMED','COMPLETED') THEN r.fare
                    WHEN r.status = 'CANCELLED' THEN r.fare - cn.refund_amount END), 0)
                                                                         AS revenue
FROM   train_schedule s
       JOIN train t ON t.train_no = s.train_no
       JOIN (SELECT c.train_no, SUM(cc.seats_per_coach) AS capacity
             FROM   coach c JOIN coach_class cc ON cc.class_code = c.class_code
             GROUP  BY c.train_no) cap ON cap.train_no = t.train_no
       LEFT JOIN reservation  r  ON r.schedule_id = s.schedule_id
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
GROUP  BY s.schedule_id, t.train_no, t.train_name, t.route_id, s.journey_date, s.sched_status, cap.capacity;

-- VIEW 2 : TRAIN UTILIZATION - one row per train across all its journeys
CREATE OR REPLACE VIEW v_train_utilization AS
SELECT v.train_no,
       v.train_name,
       v.route_id,
       so.city || '-' || sd.city                                         AS route_label,
       COUNT(*)                                                          AS journeys,
       SUM(v.capacity)                                                   AS capacity_offered,
       SUM(v.seats_occupied)                                             AS seats_occupied,
       SUM(v.waitlisted)                                                 AS waitlisted,
       SUM(v.cancelled)                                                  AS cancelled,
       SUM(v.total_bookings)                                             AS total_bookings,
       ROUND(100 * SUM(v.seats_occupied) / SUM(v.capacity), 2)           AS occupancy_pct,
       ROUND(100 * SUM(v.cancelled) / NULLIF(SUM(v.total_bookings), 0), 2) AS cancellation_rate,
       ROUND(100 * (SUM(v.seats_occupied) + SUM(v.waitlisted)) / SUM(v.capacity), 2) AS demand_pct,
       SUM(v.revenue)                                                    AS revenue
FROM   v_reservation_performance v
       JOIN route   ro ON ro.route_id = v.route_id
       JOIN station so ON so.station_code = ro.origin_code
       JOIN station sd ON sd.station_code = ro.dest_code
GROUP  BY v.train_no, v.train_name, v.route_id, so.city, sd.city;

-- VIEW 3 : TICKET DETAILS - de-normalised ticket for enquiry screens
CREATE OR REPLACE VIEW v_ticket_details AS
SELECT r.pnr, p.passenger_id, p.full_name, t.train_no, t.train_name, s.journey_date,
       r.from_station, r.to_station, r.class_code,
       c.coach_label, st.seat_no, st.berth_type,
       (rs2.km_from_origin - rs1.km_from_origin) AS distance_km,
       r.fare, r.status
FROM   reservation r
       JOIN passenger p       ON p.passenger_id = r.passenger_id
       JOIN train_schedule s  ON s.schedule_id = r.schedule_id
       JOIN train t           ON t.train_no = s.train_no
       JOIN route_stop rs1    ON rs1.route_id = t.route_id AND rs1.station_code = r.from_station
       JOIN route_stop rs2    ON rs2.route_id = t.route_id AND rs2.station_code = r.to_station
       LEFT JOIN seat st      ON st.seat_id = r.seat_id
       LEFT JOIN coach c      ON c.coach_id = st.coach_id;

COLUMN train_name   FORMAT A20
COLUMN route_label  FORMAT A22
COLUMN route_name   FORMAT A22
COLUMN station_name FORMAT A27

SELECT * FROM v_reservation_performance ORDER BY train_no, journey_date;
SELECT * FROM v_train_utilization ORDER BY occupancy_pct DESC;

-- =====================================================================================
--  PART 8 : SQL-BASED DATA PROCESSING AND ANALYSIS
-- =====================================================================================

-- Q1 TRAIN-WISE RESERVATION STATISTICS  (conditional aggregation / pivot)
SELECT t.train_no, t.train_name,
       COUNT(*)                                                    AS bookings,
       COUNT(CASE WHEN r.status = 'COMPLETED' THEN 1 END)          AS completed,
       COUNT(CASE WHEN r.status = 'CONFIRMED' THEN 1 END)          AS confirmed,
       COUNT(CASE WHEN r.status = 'WAITLIST' THEN 1 END)           AS waitlist,
       COUNT(CASE WHEN r.status = 'CANCELLED' THEN 1 END)          AS cancelled,
       ROUND(AVG(r.fare), 2)                                       AS avg_fare,
       MIN(r.booking_date)                                         AS first_booking,
       MAX(r.booking_date)                                         AS last_booking
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
GROUP  BY t.train_no, t.train_name
ORDER  BY bookings DESC;

-- Q2 STATION-WISE PASSENGER VOLUME  (boarding + alighting, stations with no traffic included)
SELECT st.station_code, st.station_name, st.city,
       NVL(b.boarding, 0)                        AS boarded,
       NVL(a.alighting, 0)                       AS alighted,
       NVL(b.boarding, 0) + NVL(a.alighting, 0)  AS total_footfall
FROM   station st
       LEFT JOIN (SELECT from_station AS code, COUNT(*) AS boarding FROM reservation
                  WHERE status IN ('CONFIRMED','COMPLETED') GROUP BY from_station) b ON b.code = st.station_code
       LEFT JOIN (SELECT to_station AS code, COUNT(*) AS alighting FROM reservation
                  WHERE status IN ('CONFIRMED','COMPLETED') GROUP BY to_station) a   ON a.code = st.station_code
ORDER  BY total_footfall DESC;

-- Q3 ROUTE UTILIZATION
SELECT ro.route_name, ro.distance_km,
       COUNT(*)                                             AS trains,
       SUM(u.journeys)                                      AS journeys,
       SUM(u.capacity_offered)                              AS seats_offered,
       SUM(u.seats_occupied)                                AS seats_sold,
       ROUND(100 * SUM(u.seats_occupied) / SUM(u.capacity_offered), 2) AS route_occupancy_pct,
       SUM(u.revenue)                                       AS revenue
FROM   v_train_utilization u JOIN route ro ON ro.route_id = u.route_id
GROUP  BY ro.route_name, ro.distance_km
ORDER  BY route_occupancy_pct DESC;

-- Q4 COACH OCCUPANCY  (per coach across all journeys of its train)
SELECT t.train_no, t.train_name, c.coach_label, c.class_code,
       cc.seats_per_coach * j.journeys                       AS seat_journeys,
       COUNT(r.pnr)                                          AS occupied,
       ROUND(100 * COUNT(r.pnr) / (cc.seats_per_coach * j.journeys), 1) AS occupancy_pct
FROM   coach c
       JOIN coach_class cc ON cc.class_code = c.class_code
       JOIN train t        ON t.train_no = c.train_no
       JOIN (SELECT train_no, COUNT(*) AS journeys FROM train_schedule GROUP BY train_no) j
                           ON j.train_no = c.train_no
       LEFT JOIN seat st   ON st.coach_id = c.coach_id
       LEFT JOIN reservation r ON r.seat_id = st.seat_id AND r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY t.train_no, t.train_name, c.coach_label, c.class_code, cc.seats_per_coach, j.journeys
ORDER  BY t.train_no, c.coach_label;

-- Q5a CANCELLATION STATISTICS BY TRAIN
SELECT t.train_no, t.train_name,
       COUNT(r.pnr)                                              AS bookings,
       COUNT(cn.cancel_id)                                       AS cancellations,
       ROUND(100 * COUNT(cn.cancel_id) / COUNT(r.pnr), 2)        AS cancel_rate_pct,
       NVL(SUM(cn.refund_amount), 0)                             AS refunded,
       NVL(SUM(CASE WHEN cn.cancel_id IS NOT NULL THEN r.fare - cn.refund_amount END), 0) AS charges_retained,
       ROUND(AVG(s.journey_date - cn.cancelled_on), 1)           AS avg_days_before_journey
FROM   reservation r
       JOIN train_schedule s     ON s.schedule_id = r.schedule_id
       JOIN train t              ON t.train_no = s.train_no
       LEFT JOIN cancellation cn ON cn.pnr = r.pnr
GROUP  BY t.train_no, t.train_name
ORDER  BY cancel_rate_pct DESC;

-- Q5b CANCELLATION REASONS  (share of total using RATIO_TO_REPORT)
SELECT reason, COUNT(*) AS cancellations,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS share_pct,
       SUM(refund_amount) AS refunded
FROM   cancellation
GROUP  BY reason
ORDER  BY cancellations DESC;

-- Q6a PEAK TRAVEL ROUTES  (ranked by passengers carried)
SELECT ro.route_name,
       COUNT(*)                                     AS passengers,
       DENSE_RANK() OVER (ORDER BY COUNT(*) DESC)   AS demand_rank
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
       JOIN route ro         ON ro.route_id = t.route_id
WHERE  r.status IN ('CONFIRMED','COMPLETED','WAITLIST')
GROUP  BY ro.route_name;

-- Q6b TOP 5 ORIGIN-DESTINATION PAIRS (peak travel segments)
SELECT fs.city || ' -> ' || ts.city AS segment, COUNT(*) AS passengers
FROM   reservation r
       JOIN station fs ON fs.station_code = r.from_station
       JOIN station ts ON ts.station_code = r.to_station
WHERE  r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY fs.city, ts.city
ORDER  BY passengers DESC
FETCH FIRST 5 ROWS ONLY;

-- Q6c PEAK TRAVEL DAYS OF THE WEEK
SELECT TO_CHAR(s.journey_date, 'DY') AS travel_day,
       COUNT(*)                      AS passengers,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS share_pct
FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
WHERE  r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY TO_CHAR(s.journey_date, 'DY')
ORDER  BY passengers DESC;

-- Q7 HIGHEST AND LOWEST UTILIZED TRAINS
SELECT CASE WHEN rk_high = 1 THEN 'HIGHEST' ELSE 'LOWEST' END AS position,
       train_no, train_name, route_label, occupancy_pct
FROM  (SELECT u.*, RANK() OVER (ORDER BY occupancy_pct DESC) AS rk_high,
                   RANK() OVER (ORDER BY occupancy_pct ASC)  AS rk_low
       FROM   v_train_utilization u)
WHERE  rk_high = 1 OR rk_low = 1;

-- Q8 PASSENGER TRAVEL FREQUENCY  (trips, distance, spend, banding with CASE)
SELECT p.passenger_id, p.full_name, p.home_city,
       COUNT(*)                     AS trips,
       SUM(v.distance_km)           AS km_travelled,
       SUM(v.fare)                  AS total_spent,
       CASE WHEN COUNT(*) >= 6 THEN 'FREQUENT'
            WHEN COUNT(*) >= 3 THEN 'REGULAR'
            ELSE 'OCCASIONAL' END   AS traveller_type
FROM   v_ticket_details v JOIN passenger p ON p.passenger_id = v.passenger_id
WHERE  v.status IN ('CONFIRMED','COMPLETED')
GROUP  BY p.passenger_id, p.full_name, p.home_city
ORDER  BY trips DESC, total_spent DESC;

-- Q9 REVENUE BY TRAIN  (route subtotals and grand total with ROLLUP)
--    The refund per ticket is worked out once in the inline view, then summed.
SELECT NVL(route_name, '** ALL ROUTES **')                                       AS route_name,
       NVL(train_name, DECODE(GROUPING(route_name), 0, '-- route total --', ' ')) AS train_name,
       SUM(amount)                                                               AS collected,
       SUM(refunded)                                                             AS refunded,
       SUM(amount) - SUM(refunded)                                               AS net_revenue
FROM  (SELECT ro.route_name, t.train_name, pm.amount,
              NVL(cn.refund_amount, 0)
              + CASE WHEN pm.pay_status = 'REFUNDED' AND cn.cancel_id IS NULL THEN pm.amount ELSE 0 END AS refunded
       FROM   payment pm
              JOIN reservation r        ON r.pnr = pm.pnr
              JOIN train_schedule s     ON s.schedule_id = r.schedule_id
              JOIN train t              ON t.train_no = s.train_no
              JOIN route ro             ON ro.route_id = t.route_id
              LEFT JOIN cancellation cn ON cn.pnr = r.pnr) x
GROUP  BY ROLLUP (x.route_name, x.train_name)
ORDER  BY GROUPING(x.route_name), x.route_name, GROUPING(x.train_name), net_revenue DESC;

-- Q10 ROUTES REQUIRING ADDITIONAL CAPACITY  (HAVING on aggregated journey data)
SELECT ro.route_name,
       COUNT(*)                                                    AS journeys,
       SUM(CASE WHEN v.occupancy_pct >= 95 THEN 1 ELSE 0 END)      AS sold_out_journeys,
       SUM(v.waitlisted)                                           AS unserved_passengers,
       ROUND(100 * SUM(v.seats_occupied) / SUM(v.capacity), 2)     AS occupancy_pct
FROM   v_reservation_performance v JOIN route ro ON ro.route_id = v.route_id
GROUP  BY ro.route_name
HAVING SUM(v.waitlisted) > 0
   AND 100 * SUM(v.seats_occupied) / SUM(v.capacity) >= 75
ORDER  BY unserved_passengers DESC;

-- =====================================================================================
--  PART 9 : ADVANCED SQL - JOINS, SUBQUERIES, CORRELATED SUBQUERIES
-- =====================================================================================

-- A1 MULTI-TABLE JOIN (10 relations) : complete travel history of one passenger.
--    Station is joined twice (boarding and destination) using table aliases.
SELECT r.pnr, t.train_no, t.train_name, s.journey_date,
       fs.station_name AS boarding, ts.station_name AS destination,
       cc.class_name, c.coach_label || '-' || st.seat_no || ' ' || st.berth_type AS seat,
       r.fare, pm.pay_mode, r.status
FROM   passenger p
       JOIN reservation r     ON r.passenger_id = p.passenger_id
       JOIN train_schedule s  ON s.schedule_id = r.schedule_id
       JOIN train t           ON t.train_no = s.train_no
       JOIN station fs        ON fs.station_code = r.from_station
       JOIN station ts        ON ts.station_code = r.to_station
       JOIN coach_class cc    ON cc.class_code = r.class_code
       JOIN payment pm        ON pm.pnr = r.pnr
       LEFT JOIN seat st      ON st.seat_id = r.seat_id
       LEFT JOIN coach c      ON c.coach_id = st.coach_id
WHERE  p.passenger_id = 1
ORDER  BY s.journey_date;

-- A2 CORRELATED SUBQUERY : trains whose occupancy is above the average occupancy of THEIR route.
--    The inner query is re-evaluated for each outer row using u.route_id.
SELECT u.train_no, u.train_name, u.route_label, u.occupancy_pct,
       (SELECT ROUND(AVG(x.occupancy_pct), 2) FROM v_train_utilization x WHERE x.route_id = u.route_id) AS route_avg_pct
FROM   v_train_utilization u
WHERE  u.occupancy_pct > (SELECT AVG(x.occupancy_pct)
                          FROM   v_train_utilization x
                          WHERE  x.route_id = u.route_id)
ORDER  BY u.route_id, u.occupancy_pct DESC;

-- A3 PASSENGERS WITH REPEATED CANCELLATIONS (2 or more) with cancellation ratio (scalar subquery)
SELECT p.passenger_id, p.full_name,
       COUNT(*)                                                           AS cancellations,
       (SELECT COUNT(*) FROM reservation x WHERE x.passenger_id = p.passenger_id) AS total_bookings,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM reservation x WHERE x.passenger_id = p.passenger_id), 1)
                                                                          AS cancel_ratio_pct,
       LISTAGG(t.train_no, ', ') WITHIN GROUP (ORDER BY s.journey_date)   AS trains_cancelled
FROM   reservation r
       JOIN passenger p      ON p.passenger_id = r.passenger_id
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
WHERE  r.status = 'CANCELLED'
GROUP  BY p.passenger_id, p.full_name
HAVING COUNT(*) >= 2
ORDER  BY cancellations DESC;

-- A4 NESTED SUBQUERY : routes whose passenger demand is above the average route demand
SELECT ro.route_name, COUNT(*) AS passengers
FROM   reservation r
       JOIN train_schedule s ON s.schedule_id = r.schedule_id
       JOIN train t          ON t.train_no = s.train_no
       JOIN route ro         ON ro.route_id = t.route_id
WHERE  r.status <> 'CANCELLED'
GROUP  BY ro.route_name
HAVING COUNT(*) > (SELECT AVG(route_pax)
                   FROM  (SELECT COUNT(*) AS route_pax
                          FROM   reservation r2
                                 JOIN train_schedule s2 ON s2.schedule_id = r2.schedule_id
                                 JOIN train t2          ON t2.train_no = s2.train_no
                          WHERE  r2.status <> 'CANCELLED'
                          GROUP  BY t2.route_id))
ORDER  BY passengers DESC;

-- A5 STATIONS HANDLING HIGHER-THAN-AVERAGE PASSENGER TRAFFIC (WITH clause + subquery)
WITH footfall AS (
  SELECT station_code, COUNT(*) AS movements
  FROM  (SELECT from_station AS station_code FROM reservation WHERE status IN ('CONFIRMED','COMPLETED')
         UNION ALL
         SELECT to_station FROM reservation WHERE status IN ('CONFIRMED','COMPLETED'))
  GROUP  BY station_code)
SELECT st.station_code, st.station_name, f.movements,
       ROUND((SELECT AVG(movements) FROM footfall), 1) AS network_avg
FROM   footfall f JOIN station st ON st.station_code = f.station_code
WHERE  f.movements > (SELECT AVG(movements) FROM footfall)
ORDER  BY f.movements DESC;

-- A6 TRAINS REQUIRING CAPACITY ENHANCEMENT (correlated NOT EXISTS + EXISTS):
--    every journey ran at >= 90% occupancy AND at least one passenger was left on the waitlist
SELECT u.train_no, u.train_name, u.occupancy_pct, u.waitlisted
FROM   v_train_utilization u
WHERE  NOT EXISTS (SELECT 1 FROM v_reservation_performance v
                   WHERE  v.train_no = u.train_no AND v.occupancy_pct < 90)
AND    EXISTS     (SELECT 1 FROM reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
                   WHERE  s.train_no = u.train_no AND r.status = 'WAITLIST');

-- A7 CORRELATED : passengers whose total spend exceeds the average spend of passengers from the same city
SELECT p.passenger_id, p.full_name, p.home_city, SUM(r.fare) AS spent
FROM   passenger p JOIN reservation r ON r.passenger_id = p.passenger_id
WHERE  r.status IN ('CONFIRMED','COMPLETED')
GROUP  BY p.passenger_id, p.full_name, p.home_city
HAVING SUM(r.fare) > (SELECT SUM(r2.fare) / COUNT(DISTINCT r2.passenger_id)
                      FROM   reservation r2 JOIN passenger p2 ON p2.passenger_id = r2.passenger_id
                      WHERE  r2.status IN ('CONFIRMED','COMPLETED')
                      AND    p2.home_city = p.home_city)
ORDER  BY p.home_city, spent DESC;

-- A8 IN / NOT IN : loyal passengers - 3 or more trips on near-full trains (>= 90% occupancy), never cancelled
SELECT p.passenger_id, p.full_name, p.home_city
FROM   passenger p
WHERE  p.passenger_id IN (SELECT r.passenger_id
                          FROM   reservation r JOIN train_schedule s ON s.schedule_id = r.schedule_id
                          WHERE  r.status IN ('CONFIRMED','COMPLETED')
                          AND    s.train_no IN (SELECT train_no FROM v_train_utilization WHERE occupancy_pct >= 90)
                          GROUP  BY r.passenger_id
                          HAVING COUNT(*) >= 3)
AND    p.passenger_id NOT IN (SELECT passenger_id FROM reservation WHERE status = 'CANCELLED')
ORDER  BY p.passenger_id;

-- A9 CORRELATED (on a WITH clause) : coaches whose occupancy % is below the average of their own train's coaches
WITH coach_occ AS (
  SELECT c.train_no, c.coach_id, c.coach_label, c.class_code,
         ROUND(100 * COUNT(r.pnr) / (cc.seats_per_coach * j.journeys), 1) AS occupancy_pct
  FROM   coach c
         JOIN coach_class cc ON cc.class_code = c.class_code
         JOIN (SELECT train_no, COUNT(*) AS journeys FROM train_schedule GROUP BY train_no) j ON j.train_no = c.train_no
         JOIN seat st ON st.coach_id = c.coach_id
         LEFT JOIN reservation r ON r.seat_id = st.seat_id AND r.status IN ('CONFIRMED','COMPLETED')
  GROUP  BY c.train_no, c.coach_id, c.coach_label, c.class_code, cc.seats_per_coach, j.journeys)
SELECT o.train_no, o.coach_label, o.class_code, o.occupancy_pct,
       (SELECT ROUND(AVG(x.occupancy_pct), 1) FROM coach_occ x WHERE x.train_no = o.train_no) AS train_avg_pct
FROM   coach_occ o
WHERE  o.occupancy_pct < (SELECT AVG(x.occupancy_pct) FROM coach_occ x WHERE x.train_no = o.train_no) - 10
ORDER  BY o.train_no, o.coach_label;

-- =====================================================================================
--  PART 10 : BTL-6 CHALLENGE - TRAIN CAPACITY RISK IDENTIFICATION MODULE
-- =====================================================================================
-- Classification rules (thresholds are stored in a table so management can tune them):
--   CAPACITY REQUIRED : occupancy >= 90%  AND  demand >= 100%  AND  cancellation rate <= 10%
--       the train is full, passengers are being turned away (waitlist), and the waitlist is
--       unlikely to clear through cancellations -> attach coaches / run a special train.
--   HIGH DEMAND       : not the above, but occupancy >= 75%  OR  demand >= 90%
--       strong but currently serviceable demand (or high demand offset by many cancellations)
--       -> monitor every week, consider extra quota on peak days.
--   NORMAL            : everything else.
CREATE TABLE risk_threshold (
  param_code   VARCHAR2(20)  CONSTRAINT pk_risk_threshold PRIMARY KEY,
  param_value  NUMBER(6,2)   NOT NULL CONSTRAINT ck_rt_value CHECK (param_value >= 0),
  description  VARCHAR2(100) NOT NULL
);
INSERT INTO risk_threshold VALUES ('CR_MIN_OCCUPANCY',  90, 'Capacity Required: minimum occupancy %');
INSERT INTO risk_threshold VALUES ('CR_MIN_DEMAND',    100, 'Capacity Required: minimum demand % (waitlist exists)');
INSERT INTO risk_threshold VALUES ('CR_MAX_CANCEL',      10, 'Capacity Required: maximum cancellation rate %');
INSERT INTO risk_threshold VALUES ('HD_MIN_OCCUPANCY',  75, 'High Demand: minimum occupancy %');
INSERT INTO risk_threshold VALUES ('HD_MIN_DEMAND',     90, 'High Demand: minimum demand %');

CREATE TABLE capacity_risk_log (
  run_date           DATE         NOT NULL,
  train_no           NUMBER(5)    NOT NULL CONSTRAINT fk_crl_train REFERENCES train(train_no),
  occupancy_pct      NUMBER(6,2),
  cancellation_rate  NUMBER(6,2),
  demand_pct         NUMBER(6,2),
  risk_status        VARCHAR2(20) NOT NULL,
  CONSTRAINT pk_capacity_risk_log PRIMARY KEY (run_date, train_no)
);
COMMIT;

CREATE OR REPLACE FUNCTION fn_capacity_risk (
  p_occupancy NUMBER, p_cancel_rate NUMBER, p_demand NUMBER
) RETURN VARCHAR2 IS
  v_cr_occ NUMBER; v_cr_dem NUMBER; v_cr_can NUMBER; v_hd_occ NUMBER; v_hd_dem NUMBER;
BEGIN
  SELECT MAX(DECODE(param_code, 'CR_MIN_OCCUPANCY', param_value)),
         MAX(DECODE(param_code, 'CR_MIN_DEMAND',    param_value)),
         MAX(DECODE(param_code, 'CR_MAX_CANCEL',    param_value)),
         MAX(DECODE(param_code, 'HD_MIN_OCCUPANCY', param_value)),
         MAX(DECODE(param_code, 'HD_MIN_DEMAND',    param_value))
  INTO   v_cr_occ, v_cr_dem, v_cr_can, v_hd_occ, v_hd_dem
  FROM   risk_threshold;

  IF p_occupancy >= v_cr_occ AND p_demand >= v_cr_dem AND NVL(p_cancel_rate, 0) <= v_cr_can THEN
    RETURN 'CAPACITY REQUIRED';
  ELSIF p_occupancy >= v_hd_occ OR p_demand >= v_hd_dem THEN
    RETURN 'HIGH DEMAND';
  END IF;
  RETURN 'NORMAL';
END;
/

COLUMN "Train"           FORMAT 99999
COLUMN "Route"           FORMAT A22
COLUMN "Risk Status"     FORMAT A18
COLUMN "Recommended Action" FORMAT A45

-- 10.1 DECISION-SUPPORT REPORT
SELECT u.train_no                                                       AS "Train",
       u.route_label                                                    AS "Route",
       u.occupancy_pct                                                  AS "Occupancy %",
       u.cancellation_rate                                              AS "Cancellation Rate",
       u.demand_pct                                                     AS "Average Demand",
       ROUND(AVG(u.occupancy_pct) OVER (PARTITION BY u.route_id), 2)    AS "Route Avg Occ %",
       fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct) AS "Risk Status",
       CASE fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct)
            WHEN 'CAPACITY REQUIRED' THEN 'Add ' || CEIL(u.waitlisted / u.journeys) || ' seat(s)/journey: attach extra coach'
            WHEN 'HIGH DEMAND'       THEN 'Monitor weekly; extra quota on peak days'
            ELSE CASE WHEN u.occupancy_pct < 50 THEN 'Under-used: review coach composition'
                      ELSE 'No action' END
       END                                                              AS "Recommended Action"
FROM   v_train_utilization u
ORDER  BY DECODE(fn_capacity_risk(u.occupancy_pct, u.cancellation_rate, u.demand_pct),
                 'CAPACITY REQUIRED', 1, 'HIGH DEMAND', 2, 3),
          u.occupancy_pct DESC;

-- 10.2 PROCEDURE : stores today's classification in CAPACITY_RISK_LOG and prints a summary
CREATE OR REPLACE PROCEDURE prc_capacity_risk_report AS
BEGIN
  DELETE FROM capacity_risk_log WHERE run_date = TRUNC(SYSDATE);
  INSERT INTO capacity_risk_log
  SELECT TRUNC(SYSDATE), train_no, occupancy_pct, cancellation_rate, demand_pct,
         fn_capacity_risk(occupancy_pct, cancellation_rate, demand_pct)
  FROM   v_train_utilization;

  DBMS_OUTPUT.PUT_LINE('TRAIN CAPACITY RISK SUMMARY - ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY'));
  FOR rec IN (SELECT risk_status, COUNT(*) AS trains,
                     LISTAGG(train_no, ', ') WITHIN GROUP (ORDER BY train_no) AS train_list
              FROM   capacity_risk_log WHERE run_date = TRUNC(SYSDATE)
              GROUP  BY risk_status ORDER BY risk_status) LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(rec.risk_status, 20) || rec.trains || ' train(s): ' || rec.train_list);
  END LOOP;
  COMMIT;
END;
/
EXEC prc_capacity_risk_report

-- 10.3 WHAT-IF ANALYSIS : tolerate up to 15% cancellations -> which trains change category?
UPDATE risk_threshold SET param_value = 15 WHERE param_code = 'CR_MAX_CANCEL';
SELECT l.train_no, l.risk_status AS current_status,
       fn_capacity_risk(l.occupancy_pct, l.cancellation_rate, l.demand_pct) AS what_if_status
FROM   capacity_risk_log l
WHERE  l.run_date = TRUNC(SYSDATE)
AND    l.risk_status <> fn_capacity_risk(l.occupancy_pct, l.cancellation_rate, l.demand_pct);
ROLLBACK;
