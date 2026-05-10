-- ================================================================
-- RideFlow — Complete Database Setup
-- Deliverable 2 (Schema) + Deliverable 3 (Views/Procs/Triggers/DCL)
-- ================================================================

SET FOREIGN_KEY_CHECKS = 0;
SET GLOBAL event_scheduler = ON;

DROP DATABASE IF EXISTS ride_sharing;
CREATE DATABASE ride_sharing CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ride_sharing;

-- ================================================================
-- SECTION 1: CORE TABLES
-- ================================================================

CREATE TABLE USERS (
    user_id     INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL,
    phone       VARCHAR(20)  NOT NULL,
    password    VARCHAR(255) NOT NULL,
    role        ENUM('rider','driver','admin') NOT NULL,
    status      ENUM('active','suspended','deleted') NOT NULL DEFAULT 'active',
    profile_photo VARCHAR(255) NULL,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_users        PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email  UNIQUE (email),
    CONSTRAINT uq_users_phone  UNIQUE (phone)
);

CREATE TABLE RIDERS (
    user_id        INT           UNSIGNED NOT NULL,
    reg_date       DATE          NOT NULL DEFAULT (CURRENT_DATE),
    avg_rating     DECIMAL(3,2)  NULL CHECK (avg_rating BETWEEN 0.00 AND 5.00),
    wallet_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00 CHECK (wallet_balance >= 0),
    wallet_pin     VARCHAR(4)    NOT NULL DEFAULT '1234',
    CONSTRAINT pk_riders       PRIMARY KEY (user_id),
    CONSTRAINT fk_riders_users FOREIGN KEY (user_id) REFERENCES USERS(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE DRIVERS (
    user_id      INT          UNSIGNED NOT NULL,
    license      VARCHAR(50)  NOT NULL,
    cnic         VARCHAR(20)  NOT NULL,
    city         VARCHAR(100) NOT NULL DEFAULT 'Islamabad',
    avail_status ENUM('available','on_trip','offline') NOT NULL DEFAULT 'offline',
    verif_status ENUM('pending','verified','rejected')  NOT NULL DEFAULT 'pending',
    avg_rating   DECIMAL(3,2) NULL CHECK (avg_rating BETWEEN 0.00 AND 5.00),
    CONSTRAINT pk_drivers          PRIMARY KEY (user_id),
    CONSTRAINT uq_drivers_license  UNIQUE (license),
    CONSTRAINT uq_drivers_cnic     UNIQUE (cnic),
    CONSTRAINT fk_drivers_users    FOREIGN KEY (user_id) REFERENCES USERS(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE ADMINS (
    user_id  INT        UNSIGNED NOT NULL,
    is_super TINYINT(1) NOT NULL DEFAULT 0 CHECK (is_super IN (0,1)),
    CONSTRAINT pk_admins       PRIMARY KEY (user_id),
    CONSTRAINT fk_admins_users FOREIGN KEY (user_id) REFERENCES USERS(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE VEHICLES (
    veh_id   INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    make     VARCHAR(50)  NOT NULL,
    model    VARCHAR(50)  NOT NULL,
    year_    YEAR         NOT NULL,
    color    VARCHAR(30)  NOT NULL,
    plate    VARCHAR(20)  NOT NULL,
    type_    ENUM('sedan','suv','bike','van','rickshaw','other') NOT NULL,
    verif_st ENUM('pending','verified','rejected') NOT NULL DEFAULT 'pending',
    CONSTRAINT pk_vehicles        PRIMARY KEY (veh_id),
    CONSTRAINT uq_vehicles_plate  UNIQUE (plate),
    CONSTRAINT chk_vehicles_year  CHECK (year_ >= 1990)
);

CREATE TABLE OWNS (
    user_id INT UNSIGNED NOT NULL,
    veh_id  INT UNSIGNED NOT NULL,
    CONSTRAINT pk_owns         PRIMARY KEY (user_id, veh_id),
    CONSTRAINT fk_owns_driver  FOREIGN KEY (user_id) REFERENCES DRIVERS(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_owns_vehicle FOREIGN KEY (veh_id)  REFERENCES VEHICLES(veh_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE FARE_RULES (
    rule_id   INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    v_type    ENUM('sedan','suv','bike','van','rickshaw','other') NOT NULL,
    base_rate DECIMAL(10,2) NOT NULL CHECK (base_rate >= 0),
    km_rate   DECIMAL(10,2) NOT NULL CHECK (km_rate   >= 0),
    min_rate  DECIMAL(10,2) NOT NULL CHECK (min_rate  >= 0),
    per_min_rate DECIMAL(10,2) NOT NULL DEFAULT 5.00 CHECK (per_min_rate >= 0),
    surge     DECIMAL(5,2)  NOT NULL DEFAULT 1.00 CHECK (surge >= 1.00),
    active    TINYINT(1)    NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    CONSTRAINT pk_fare_rules  PRIMARY KEY (rule_id),
    CONSTRAINT uq_fare_vtype  UNIQUE (v_type)
);

CREATE TABLE PROMO_CODES (
    promo_id INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    code     VARCHAR(30)  NOT NULL,
    disc_pct DECIMAL(5,2) NULL CHECK (disc_pct BETWEEN 0 AND 100),
    disc_amt DECIMAL(10,2) NULL CHECK (disc_amt >= 0),
    count    INT          UNSIGNED NOT NULL DEFAULT 0,
    exp_date DATE         NOT NULL,
    active   TINYINT(1)   NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    `limit`  INT          UNSIGNED NOT NULL DEFAULT 100,
    CONSTRAINT pk_promo_codes     PRIMARY KEY (promo_id),
    CONSTRAINT uq_promo_code      UNIQUE (code),
    CONSTRAINT chk_promo_discount CHECK (
        (disc_pct IS NOT NULL AND disc_amt IS NULL) OR
        (disc_pct IS NULL     AND disc_amt IS NOT NULL)
    )
);

CREATE TABLE RIDES (
    ride_id   INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    rider_id  INT          UNSIGNED NOT NULL,
    driver_id INT          UNSIGNED NULL,
    veh_id    INT          UNSIGNED NULL,
    pickup    VARCHAR(255) NOT NULL,
    dropoff   VARCHAR(255) NOT NULL,
    city      VARCHAR(100) NOT NULL DEFAULT 'Islamabad',
    status    ENUM('requested','accepted','en_route','in_progress','waiting_payment','completed','cancelled') NOT NULL DEFAULT 'requested',
    fare      DECIMAL(10,2) NULL CHECK (fare >= 0),
    dist_km   DECIMAL(8,2)  NULL CHECK (dist_km >= 0),
    sched_at  DATETIME      NULL,
    req_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rides         PRIMARY KEY (ride_id),
    CONSTRAINT fk_rides_rider   FOREIGN KEY (rider_id)  REFERENCES RIDERS(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_rides_driver  FOREIGN KEY (driver_id) REFERENCES DRIVERS(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_rides_vehicle FOREIGN KEY (veh_id)    REFERENCES VEHICLES(veh_id)
        ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE PAYMENTS (
    pay_id   INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    ride_id  INT          UNSIGNED NOT NULL,
    amount   DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    method   ENUM('cash','card','wallet','online') NOT NULL,
    status   ENUM('pending','completed','refunded','failed') NOT NULL DEFAULT 'pending',
    date     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    discount DECIMAL(10,2) NOT NULL DEFAULT 0.00 CHECK (discount >= 0),
    CONSTRAINT pk_payments       PRIMARY KEY (pay_id),
    CONSTRAINT uq_payments_ride  UNIQUE (ride_id),
    CONSTRAINT fk_payments_ride  FOREIGN KEY (ride_id) REFERENCES RIDES(ride_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE APPLIES (
    pay_id   INT UNSIGNED NOT NULL,
    promo_id INT UNSIGNED NOT NULL,
    CONSTRAINT pk_applies          PRIMARY KEY (pay_id, promo_id),
    CONSTRAINT uq_applies_pay      UNIQUE (pay_id),
    CONSTRAINT fk_applies_payment  FOREIGN KEY (pay_id)   REFERENCES PAYMENTS(pay_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_applies_promo    FOREIGN KEY (promo_id) REFERENCES PROMO_CODES(promo_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE RIDE_HISTORY (
    hist_id  INT       UNSIGNED NOT NULL AUTO_INCREMENT,
    ride_id  INT       UNSIGNED NOT NULL,
    status   ENUM('completed','cancelled','no_show') NOT NULL,
    archived TINYINT(1) NOT NULL DEFAULT 0 CHECK (archived IN (0,1)),
    arch_at  DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ride_history       PRIMARY KEY (hist_id),
    CONSTRAINT uq_ride_history_ride  UNIQUE (ride_id),
    CONSTRAINT fk_ride_history_ride  FOREIGN KEY (ride_id) REFERENCES RIDES(ride_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE DRIVER_EARNINGS (
    earn_id   INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    driver_id INT          UNSIGNED NOT NULL,
    ride_id   INT          UNSIGNED NOT NULL,
    gross     DECIMAL(10,2) NOT NULL CHECK (gross    >= 0),
    comm_pct  DECIMAL(5,2)  NOT NULL DEFAULT 20.00 CHECK (comm_pct BETWEEN 0 AND 100),
    net       DECIMAL(10,2) NOT NULL CHECK (net      >= 0),
    payout_st ENUM('pending','paid','on_hold') NOT NULL DEFAULT 'pending',
    earn_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_driver_earnings      PRIMARY KEY (earn_id),
    CONSTRAINT uq_driver_earnings_ride UNIQUE (ride_id),
    CONSTRAINT fk_earnings_driver      FOREIGN KEY (driver_id) REFERENCES DRIVERS(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_earnings_ride        FOREIGN KEY (ride_id)   REFERENCES RIDES(ride_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE RATINGS (
    rating_id INT        UNSIGNED NOT NULL AUTO_INCREMENT,
    ride_id   INT        UNSIGNED NOT NULL,
    rater_id  INT        UNSIGNED NOT NULL,
    score     TINYINT    UNSIGNED NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment   TEXT       NULL,
    time      DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_ratings            PRIMARY KEY (rating_id),
    CONSTRAINT uq_rating_ride_rater  UNIQUE (ride_id, rater_id),
    CONSTRAINT fk_ratings_ride       FOREIGN KEY (ride_id)  REFERENCES RIDES(ride_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ratings_rater      FOREIGN KEY (rater_id) REFERENCES USERS(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Additional tables for full functionality
CREATE TABLE ADMIN_NOTIFICATIONS (
    notif_id   INT       UNSIGNED NOT NULL AUTO_INCREMENT,
    message    TEXT      NOT NULL,
    driver_id  INT       UNSIGNED NULL,
    is_read    TINYINT(1) NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
    created_at DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_admin_notifications PRIMARY KEY (notif_id),
    CONSTRAINT fk_notif_driver        FOREIGN KEY (driver_id) REFERENCES DRIVERS(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE TABLE COMPLAINTS (
    comp_id    INT          UNSIGNED NOT NULL AUTO_INCREMENT,
    ride_id    INT          UNSIGNED NULL,
    user_id    INT          UNSIGNED NOT NULL,
    subject    VARCHAR(200) NOT NULL,
    description TEXT        NULL,
    status     ENUM('open','in_review','resolved','closed') NOT NULL DEFAULT 'open',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_complaints      PRIMARY KEY (comp_id),
    CONSTRAINT fk_comp_ride       FOREIGN KEY (ride_id)  REFERENCES RIDES(ride_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_comp_user       FOREIGN KEY (user_id)  REFERENCES USERS(user_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

SET FOREIGN_KEY_CHECKS = 1;

-- ================================================================
-- SECTION 2: INDEXES
-- ================================================================
CREATE INDEX idx_rides_rider_id  ON RIDES(rider_id);
CREATE INDEX idx_rides_driver_id ON RIDES(driver_id);
CREATE INDEX idx_rides_status    ON RIDES(status);
CREATE INDEX idx_rides_city      ON RIDES(city);
CREATE INDEX idx_rides_req_at    ON RIDES(req_at);
CREATE INDEX idx_drivers_city    ON DRIVERS(city);
CREATE INDEX idx_payments_status ON PAYMENTS(status);
CREATE INDEX idx_ratings_ride    ON RATINGS(ride_id);

-- ================================================================
-- SECTION 3: VIEWS
-- ================================================================

-- View 1: All ongoing trips with rider and driver details
CREATE OR REPLACE VIEW ActiveRidesView AS
SELECT
    r.ride_id,
    r.status,
    r.pickup,
    r.dropoff,
    r.city,
    r.fare,
    r.dist_km,
    r.req_at,
    u_rider.full_name   AS rider_name,
    u_rider.phone       AS rider_phone,
    u_driver.full_name  AS driver_name,
    u_driver.phone      AS driver_phone,
    d.avail_status      AS driver_avail_status,
    v.make              AS vehicle_make,
    v.model             AS vehicle_model,
    v.plate             AS vehicle_plate,
    v.type_             AS vehicle_type
FROM RIDES r
JOIN USERS u_rider   ON r.rider_id  = u_rider.user_id
LEFT JOIN USERS u_driver  ON r.driver_id = u_driver.user_id
LEFT JOIN DRIVERS d       ON r.driver_id = d.user_id
LEFT JOIN VEHICLES v      ON r.veh_id    = v.veh_id
WHERE r.status IN ('requested','accepted','in_progress');

-- View 2: Drivers with average rating above 4.5
CREATE OR REPLACE VIEW TopDriversView AS
SELECT
    d.user_id           AS driver_id,
    u.full_name         AS driver_name,
    u.phone,
    d.city,
    d.avail_status,
    d.verif_status,
    d.avg_rating,
    COUNT(DISTINCT r.ride_id) AS total_rides,
    COALESCE(SUM(de.net), 0) AS total_earnings
FROM DRIVERS d
JOIN USERS u              ON d.user_id  = u.user_id
LEFT JOIN RIDES r         ON d.user_id  = r.driver_id AND r.status = 'completed'
LEFT JOIN DRIVER_EARNINGS de ON d.user_id = de.driver_id
WHERE d.avg_rating >= 4.5 AND d.verif_status = 'verified'
GROUP BY d.user_id, u.full_name, u.phone, d.city, d.avail_status, d.verif_status, d.avg_rating;

-- View 3: Full trip report (for admin reports)
CREATE OR REPLACE VIEW FullTripReportView AS
SELECT
    r.ride_id,
    r.city,
    r.pickup,
    r.dropoff,
    r.status,
    r.fare,
    r.dist_km,
    r.req_at,
    u_rider.full_name   AS rider_name,
    u_rider.email       AS rider_email,
    u_driver.full_name  AS driver_name,
    v.make              AS vehicle_make,
    v.model             AS vehicle_model,
    v.type_             AS vehicle_type,
    v.plate             AS vehicle_plate,
    p.amount            AS payment_amount,
    p.method            AS payment_method,
    p.status            AS payment_status,
    p.discount          AS discount_applied,
    pc.code             AS promo_code_used
FROM RIDES r
JOIN USERS u_rider        ON r.rider_id  = u_rider.user_id
LEFT JOIN USERS u_driver  ON r.driver_id = u_driver.user_id
LEFT JOIN VEHICLES v      ON r.veh_id    = v.veh_id
LEFT JOIN PAYMENTS p      ON r.ride_id   = p.ride_id
LEFT JOIN APPLIES ap      ON p.pay_id    = ap.pay_id
LEFT JOIN PROMO_CODES pc  ON ap.promo_id = pc.promo_id;

-- ================================================================
-- SECTION 4: STORED PROCEDURES
-- ================================================================
DELIMITER $$

-- Procedure: Suspend a user (Only super admin can suspend, cannot suspend self)
CREATE PROCEDURE SuspendUser(
    IN p_admin_id INT UNSIGNED,
    IN p_target_user_id INT UNSIGNED
)
BEGIN
    DECLARE v_is_super TINYINT(1);
    
    -- 1. Prevent self-suspension
    IF p_admin_id = p_target_user_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Super admin cannot suspend themselves.';
    END IF;
    
    -- 2. Verify admin is a super admin
    SELECT is_super INTO v_is_super FROM ADMINS WHERE user_id = p_admin_id;
    
    IF v_is_super IS NULL OR v_is_super = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a super admin can suspend users.';
    END IF;
    
    -- 3. Perform suspension
    UPDATE USERS SET status = 'suspended' WHERE user_id = p_target_user_id;
END$$

-- Procedure: Calculate fare using distance and vehicle type with surge
CREATE PROCEDURE CalculateFare(
    IN  p_ride_id  INT UNSIGNED,
    IN  p_dist_km  DECIMAL(8,2),
    IN  p_duration_mins INT,
    OUT p_fare     DECIMAL(10,2)
)
BEGIN
    DECLARE v_base_rate DECIMAL(10,2) DEFAULT 50.00;
    DECLARE v_km_rate   DECIMAL(10,2) DEFAULT 20.00;
    DECLARE v_min_rate  DECIMAL(10,2) DEFAULT 80.00;
    DECLARE v_per_min_rate DECIMAL(10,2) DEFAULT 5.00;
    DECLARE v_surge     DECIMAL(5,2)  DEFAULT 1.00;
    DECLARE v_veh_type  VARCHAR(20);
    DECLARE v_raw_fare  DECIMAL(10,2);
    DECLARE v_hour      INT;

    -- Get vehicle type for this ride
    SELECT v.type_ INTO v_veh_type
    FROM RIDES r
    JOIN VEHICLES v ON r.veh_id = v.veh_id
    WHERE r.ride_id = p_ride_id
    LIMIT 1;

    -- Get fare rule for vehicle type
    IF v_veh_type IS NOT NULL THEN
        SELECT base_rate, km_rate, min_rate, per_min_rate, surge
        INTO v_base_rate, v_km_rate, v_min_rate, v_per_min_rate, v_surge
        FROM FARE_RULES
        WHERE v_type = v_veh_type AND active = 1
        LIMIT 1;
    END IF;

    -- Apply automatic surge during peak hours (8-10 AM and 5-8 PM)
    SET v_hour = HOUR(NOW());
    IF (v_hour BETWEEN 8 AND 10) OR (v_hour BETWEEN 17 AND 20) THEN
        SET v_surge = GREATEST(v_surge, 1.50);
    END IF;

    -- Calculate fare: max of min_rate OR (base + km*dist + min*duration) * surge
    SET v_raw_fare = (v_base_rate + (v_km_rate * p_dist_km) + (v_per_min_rate * p_duration_mins)) * v_surge;
    SET p_fare     = GREATEST(v_min_rate, v_raw_fare);

    -- Update the ride record
    UPDATE RIDES
    SET fare    = p_fare,
        dist_km = p_dist_km
    WHERE ride_id = p_ride_id;
END$$

-- Procedure: Get revenue summary by city and date range
CREATE PROCEDURE GetRevenueByCity(
    IN p_start DATE,
    IN p_end   DATE
)
BEGIN
    SELECT
        r.city,
        COUNT(p.pay_id)       AS total_payments,
        SUM(p.amount)         AS total_revenue,
        SUM(p.discount)       AS total_discounts,
        AVG(p.amount)         AS avg_fare,
        SUM(CASE WHEN p.method = 'cash'   THEN p.amount ELSE 0 END) AS cash_revenue,
        SUM(CASE WHEN p.method = 'card'   THEN p.amount ELSE 0 END) AS card_revenue,
        SUM(CASE WHEN p.method = 'wallet' THEN p.amount ELSE 0 END) AS wallet_revenue,
        SUM(CASE WHEN p.method = 'online' THEN p.amount ELSE 0 END) AS online_revenue
    FROM PAYMENTS p
    JOIN RIDES r ON p.ride_id = r.ride_id
    WHERE p.status = 'completed'
      AND DATE(p.date) BETWEEN p_start AND p_end
    GROUP BY r.city
    ORDER BY total_revenue DESC;
END$$

-- Procedure: Get driver performance stats
CREATE PROCEDURE GetDriverStats()
BEGIN
    SELECT
        d.user_id         AS driver_id,
        u.full_name       AS driver_name,
        d.city,
        d.avg_rating,
        d.avail_status,
        COUNT(r.ride_id)             AS total_trips,
        COALESCE(SUM(de.gross), 0)   AS total_gross,
        COALESCE(SUM(de.net), 0)     AS total_net_earnings,
        AVG(de.comm_pct)             AS avg_commission
    FROM DRIVERS d
    JOIN USERS u               ON d.user_id  = u.user_id
    LEFT JOIN RIDES r          ON d.user_id  = r.driver_id AND r.status = 'completed'
    LEFT JOIN DRIVER_EARNINGS de ON d.user_id = de.driver_id
    GROUP BY d.user_id, u.full_name, d.city, d.avg_rating, d.avail_status
    ORDER BY total_trips DESC;
END$$

-- Procedure: Request Payment (Calculates fare and waits for rider)
CREATE PROCEDURE CompleteRide(
    IN p_ride_id       INT UNSIGNED,
    IN p_dist_km       DECIMAL(8,2),
    IN p_duration_mins INT,
    IN p_comm_pct      DECIMAL(5,2),
    OUT p_fare         DECIMAL(10,2),
    OUT p_net_earn     DECIMAL(10,2)
)
BEGIN
    -- Calculate fare via CalculateFare procedure
    CALL CalculateFare(p_ride_id, p_dist_km, p_duration_mins, p_fare);

    -- Mark ride as waiting for payment
    UPDATE RIDES SET status = 'waiting_payment' WHERE ride_id = p_ride_id;

    -- Net earnings handled later, set to 0 for now
    SET p_net_earn = 0;
END$$

DELIMITER ;

-- ================================================================
-- SECTION 5: TRIGGERS
-- ================================================================
DELIMITER $$

-- Trigger 1: When payment is marked 'completed', archive the ride
CREATE TRIGGER after_payment_completed
AFTER UPDATE ON PAYMENTS
FOR EACH ROW
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        -- Ensure ride is marked completed
        UPDATE RIDES SET status = 'completed' WHERE ride_id = NEW.ride_id AND status != 'completed';

        -- Archive if not already done
        INSERT INTO RIDE_HISTORY (ride_id, status)
        VALUES (NEW.ride_id, 'completed')
        ON DUPLICATE KEY UPDATE status = 'completed', arch_at = NOW();
    END IF;
END$$

-- Trigger 2: On new rating — update driver avg_rating & flag if below 3.5
CREATE TRIGGER after_rating_insert
AFTER INSERT ON RATINGS
FOR EACH ROW
BEGIN
    DECLARE v_avg_rating  DECIMAL(3,2);
    DECLARE v_driver_id   INT UNSIGNED;
    DECLARE v_driver_name VARCHAR(100);

    -- Find driver for this ride
    SELECT driver_id INTO v_driver_id FROM RIDES WHERE ride_id = NEW.ride_id;

    IF v_driver_id IS NOT NULL THEN
        -- Recalculate driver average rating
        SELECT AVG(rt.score) INTO v_avg_rating
        FROM RATINGS rt
        JOIN RIDES ri ON rt.ride_id = ri.ride_id
        WHERE ri.driver_id = v_driver_id;

        -- Update DRIVERS table
        UPDATE DRIVERS SET avg_rating = v_avg_rating WHERE user_id = v_driver_id;

        -- Also update rider avg rating if the rater is a driver
        -- (meaning they are rating the rider — update rider avg)
        -- (This logic handled separately for simplicity)

        -- Flag driver if below 3.5
        IF v_avg_rating < 3.5 THEN
            SELECT u.full_name INTO v_driver_name
            FROM USERS u WHERE u.user_id = v_driver_id;

            INSERT INTO ADMIN_NOTIFICATIONS (message, driver_id)
            VALUES (
                CONCAT('⚠️ ALERT: Driver "', v_driver_name, '" (ID:', v_driver_id,
                       ') average rating dropped to ', ROUND(v_avg_rating, 2),
                       '. Account may require review.'),
                v_driver_id
            );
        END IF;
    END IF;
END$$

-- Trigger 3: When promo is applied, increment usage count & auto-deactivate if limit reached
CREATE TRIGGER after_promo_applied
AFTER INSERT ON APPLIES
FOR EACH ROW
BEGIN
    -- Increment usage count
    UPDATE PROMO_CODES
    SET count = count + 1
    WHERE promo_id = NEW.promo_id;

    -- Auto-deactivate if limit reached
    UPDATE PROMO_CODES
    SET active = 0
    WHERE promo_id = NEW.promo_id AND count >= `limit`;
END$$

-- Trigger 4: When ride is cancelled, archive it
CREATE TRIGGER after_ride_cancelled
AFTER UPDATE ON RIDES
FOR EACH ROW
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status != 'cancelled' THEN
        INSERT INTO RIDE_HISTORY (ride_id, status)
        VALUES (NEW.ride_id, 'cancelled')
        ON DUPLICATE KEY UPDATE status = 'cancelled', arch_at = NOW();

        -- Free the driver if one was assigned
        IF NEW.driver_id IS NOT NULL THEN
            UPDATE DRIVERS SET avail_status = 'available' WHERE user_id = NEW.driver_id;
        END IF;
    END IF;
END$$

DELIMITER ;

-- ================================================================
-- SECTION 6: SCHEDULED EVENTS
-- ================================================================

-- Event: Expire promo codes nightly at midnight
CREATE EVENT IF NOT EXISTS expire_promo_codes
ON SCHEDULE EVERY 1 DAY
STARTS (DATE(NOW()) + INTERVAL 1 DAY + INTERVAL 0 HOUR)
DO
    UPDATE PROMO_CODES
    SET active = 0
    WHERE exp_date < CURDATE() AND active = 1;

-- Event: Auto-archive old completed/cancelled rides (older than 30 days)
CREATE EVENT IF NOT EXISTS auto_archive_old_rides
ON SCHEDULE EVERY 1 WEEK
STARTS (DATE(NOW()) + INTERVAL 1 DAY)
DO
    UPDATE RIDE_HISTORY
    SET archived = 1
    WHERE arch_at < DATE_SUB(NOW(), INTERVAL 30 DAY) AND archived = 0;

-- ================================================================
-- SECTION 7: DCL — ROLES AND PERMISSIONS
-- ================================================================

-- Create MySQL application users/roles
CREATE USER IF NOT EXISTS 'rider_app'@'%'    IDENTIFIED BY 'rider_secure_pass_2026';
CREATE USER IF NOT EXISTS 'driver_app'@'%'   IDENTIFIED BY 'driver_secure_pass_2026';
CREATE USER IF NOT EXISTS 'admin_app'@'%'    IDENTIFIED BY 'admin_secure_pass_2026';
CREATE USER IF NOT EXISTS 'support_app'@'%'  IDENTIFIED BY 'support_secure_pass_2026';

-- ── Rider Role Permissions ──────────────────────────────────────
-- Riders can book rides and make payments
GRANT SELECT, INSERT            ON ride_sharing.RIDES          TO 'rider_app'@'%';
GRANT SELECT, INSERT            ON ride_sharing.PAYMENTS       TO 'rider_app'@'%';
GRANT SELECT, INSERT            ON ride_sharing.RATINGS        TO 'rider_app'@'%';
GRANT SELECT                    ON ride_sharing.DRIVERS        TO 'rider_app'@'%';
GRANT SELECT                    ON ride_sharing.VEHICLES       TO 'rider_app'@'%';
GRANT SELECT                    ON ride_sharing.FARE_RULES     TO 'rider_app'@'%';
GRANT SELECT                    ON ride_sharing.PROMO_CODES    TO 'rider_app'@'%';
GRANT SELECT, INSERT            ON ride_sharing.APPLIES        TO 'rider_app'@'%';
GRANT SELECT, INSERT            ON ride_sharing.COMPLAINTS     TO 'rider_app'@'%';
GRANT SELECT, UPDATE            ON ride_sharing.RIDERS         TO 'rider_app'@'%';

-- ── Driver Role Permissions ─────────────────────────────────────
-- Drivers can view/update rides and see their own earnings
GRANT SELECT                    ON ride_sharing.RIDES          TO 'driver_app'@'%';
GRANT SELECT, UPDATE            ON ride_sharing.DRIVERS        TO 'driver_app'@'%';
GRANT SELECT                    ON ride_sharing.DRIVER_EARNINGS TO 'driver_app'@'%';
GRANT SELECT                    ON ride_sharing.VEHICLES       TO 'driver_app'@'%';
GRANT SELECT                    ON ride_sharing.RIDE_HISTORY   TO 'driver_app'@'%';

-- ── Admin Role Permissions ──────────────────────────────────────
GRANT ALL PRIVILEGES ON ride_sharing.* TO 'admin_app'@'%';

-- ── Support Role Permissions (Read-only, no DELETE) ─────────────
GRANT SELECT ON ride_sharing.USERS          TO 'support_app'@'%';
GRANT SELECT ON ride_sharing.RIDES          TO 'support_app'@'%';
GRANT SELECT ON ride_sharing.PAYMENTS       TO 'support_app'@'%';
GRANT SELECT ON ride_sharing.RATINGS        TO 'support_app'@'%';
GRANT SELECT ON ride_sharing.COMPLAINTS     TO 'support_app'@'%';
GRANT SELECT ON ride_sharing.RIDE_HISTORY   TO 'support_app'@'%';
-- Explicitly REVOKE DELETE to prevent data deletion by support
REVOKE DELETE ON ride_sharing.RIDES    FROM 'support_app'@'%';
REVOKE DELETE ON ride_sharing.PAYMENTS FROM 'support_app'@'%';
REVOKE DELETE ON ride_sharing.USERS    FROM 'support_app'@'%';

FLUSH PRIVILEGES;

-- ================================================================
-- SECTION 8: REQUIRED SQL QUERIES (D3 Requirements)
-- ================================================================

-- ── Q1: List all COMPLETED rides for a specific rider, ordered by date ──
-- USAGE: Replace ? with rider's user_id
-- SELECT r.ride_id, r.pickup, r.dropoff, r.city, r.fare, r.dist_km, r.req_at,
--        u_d.full_name AS driver_name, v.make, v.model, v.plate
-- FROM RIDES r
-- LEFT JOIN USERS u_d ON r.driver_id = u_d.user_id
-- LEFT JOIN VEHICLES v ON r.veh_id = v.veh_id
-- WHERE r.rider_id = ? AND r.status = 'completed'
-- ORDER BY r.req_at DESC;

-- ── Q2: List all drivers in a city, ordered by rating ──
-- USAGE: Replace ? with city name
-- SELECT d.user_id, u.full_name, d.city, d.avg_rating, d.avail_status, d.verif_status
-- FROM DRIVERS d
-- JOIN USERS u ON d.user_id = u.user_id
-- WHERE d.city = ?
-- ORDER BY d.avg_rating DESC;

-- ── Q3 (Aggregate): Total revenue per city using SUM() ──
-- SELECT r.city,
--        COUNT(p.pay_id)   AS total_rides,
--        SUM(p.amount)     AS total_revenue,
--        AVG(p.amount)     AS avg_fare
-- FROM PAYMENTS p
-- JOIN RIDES r ON p.ride_id = r.ride_id
-- WHERE p.status = 'completed'
-- GROUP BY r.city
-- ORDER BY total_revenue DESC;

-- ── Q4 (HAVING): Drivers with AVG rating < 3.5 (needs review) ──
-- SELECT d.user_id, u.full_name, d.city,
--        AVG(rt.score) AS avg_score,
--        COUNT(rt.rating_id) AS rating_count
-- FROM DRIVERS d
-- JOIN USERS u ON d.user_id = u.user_id
-- JOIN RIDES r ON d.user_id = r.driver_id
-- JOIN RATINGS rt ON r.ride_id = rt.ride_id
-- GROUP BY d.user_id, u.full_name, d.city
-- HAVING AVG(rt.score) < 3.5
-- ORDER BY avg_score ASC;

-- ── Q5 (COUNT + GROUP BY): Number of trips per driver ──
-- SELECT d.user_id, u.full_name, d.city,
--        COUNT(r.ride_id) AS completed_trips
-- FROM DRIVERS d
-- JOIN USERS u ON d.user_id = u.user_id
-- LEFT JOIN RIDES r ON d.user_id = r.driver_id AND r.status = 'completed'
-- GROUP BY d.user_id, u.full_name, d.city
-- ORDER BY completed_trips DESC;

-- ── Q6 (INNER JOIN): Full trip report ──
-- SELECT r.ride_id, r.city, r.pickup, r.dropoff, r.status, r.fare, r.dist_km, r.req_at,
--        u_r.full_name AS rider_name, u_r.email AS rider_email,
--        u_d.full_name AS driver_name,
--        v.make, v.model, v.plate, v.type_,
--        p.amount, p.method, p.status AS payment_status
-- FROM RIDES r
-- INNER JOIN USERS u_r   ON r.rider_id  = u_r.user_id
-- INNER JOIN USERS u_d   ON r.driver_id = u_d.user_id
-- INNER JOIN VEHICLES v  ON r.veh_id    = v.veh_id
-- INNER JOIN PAYMENTS p  ON r.ride_id   = p.ride_id
-- ORDER BY r.req_at DESC;

-- ── Q7 (LEFT JOIN): All riders, including those with NO completed rides ──
-- SELECT u.user_id, u.full_name, u.email,
--        ri.wallet_balance, ri.avg_rating,
--        COUNT(r.ride_id) AS total_rides,
--        COALESCE(SUM(p.amount), 0) AS total_spent
-- FROM USERS u
-- JOIN RIDERS ri ON u.user_id = ri.user_id
-- LEFT JOIN RIDES r    ON u.user_id = r.rider_id AND r.status = 'completed'
-- LEFT JOIN PAYMENTS p ON r.ride_id = p.ride_id  AND p.status = 'completed'
-- GROUP BY u.user_id, u.full_name, u.email, ri.wallet_balance, ri.avg_rating
-- ORDER BY total_rides DESC;

-- ── Q8 (JOIN Payments + PromoCodes): Discount usage per ride ──
-- SELECT r.ride_id, u.full_name AS rider_name, r.city,
--        p.amount, p.discount, p.method,
--        pc.code AS promo_code, pc.disc_pct, pc.disc_amt
-- FROM PAYMENTS p
-- JOIN RIDES r       ON p.ride_id   = r.ride_id
-- JOIN USERS u       ON r.rider_id  = u.user_id
-- JOIN APPLIES ap    ON p.pay_id    = ap.pay_id
-- JOIN PROMO_CODES pc ON ap.promo_id = pc.promo_id
-- ORDER BY p.date DESC;
