-- ================================================================
-- RideFlow — Seed Data
-- All passwords are hashed version of: password123
-- Hash: $2b$10$YKVkH1gU9bQ5G7gCr2vFvuSoaZQ1CwfAzGyjQqhFJ8KjFqHXbZvFi
-- Run this AFTER schema.sql
-- Better: run `node seed.js` which auto-hashes passwords
-- ================================================================
USE ride_sharing;

-- ── USERS ──────────────────────────────────────────────────────
-- Password for all: password123 (hashed by seed.js)
-- For direct SQL insert, use this bcrypt hash (cost 10):
-- $2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi

SET @pw = '$2b$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi';

INSERT INTO USERS (full_name, email, phone, password, role, status) VALUES
-- Admins
('Super Admin',      'admin@rideflow.pk',       '03001111111', @pw, 'admin',  'active'),
('Support Admin',    'support@rideflow.pk',     '03001111112', @pw, 'admin',  'active'),
-- Drivers
('Ahmed Raza',       'ahmed@driver.pk',         '03211234567', @pw, 'driver', 'active'),
('Bilal Khan',       'bilal@driver.pk',         '03211234568', @pw, 'driver', 'active'),
('Usman Tariq',      'usman@driver.pk',         '03211234569', @pw, 'driver', 'active'),
('Zubair Ali',       'zubair@driver.pk',        '03211234570', @pw, 'driver', 'active'),
('Faisal Mehmood',   'faisal@driver.pk',        '03211234571', @pw, 'driver', 'active'),
-- Riders
('Sara Malik',       'sara@rider.pk',           '03331234567', @pw, 'rider',  'active'),
('Ayesha Khan',      'ayesha@rider.pk',         '03331234568', @pw, 'rider',  'active'),
('Hassan Iqbal',     'hassan@rider.pk',         '03331234569', @pw, 'rider',  'active'),
('Fatima Zahra',     'fatima@rider.pk',         '03331234570', @pw, 'rider',  'active'),
('Omar Siddiqui',    'omar@rider.pk',           '03331234571', @pw, 'rider',  'active');

-- ── ADMINS ─────────────────────────────────────────────────────
INSERT INTO ADMINS (user_id, is_super) VALUES
(1, 1),   -- Super Admin
(2, 0);   -- Support Admin

-- ── DRIVERS ────────────────────────────────────────────────────
INSERT INTO DRIVERS (user_id, license, cnic, city, avail_status, verif_status, avg_rating) VALUES
(3, 'LHR-2021-001', '35201-1234567-1', 'Islamabad', 'available', 'verified', 4.80),
(4, 'ISB-2022-002', '35202-2345678-2', 'Islamabad', 'available', 'verified', 4.60),
(5, 'KHI-2020-003', '35203-3456789-3', 'Lahore',    'offline',   'verified', 4.20),
(6, 'LHR-2019-004', '35204-4567890-4', 'Islamabad', 'offline',   'verified', 3.90),
(7, 'ISB-2023-005', '35205-5678901-5', 'Karachi',   'available', 'pending',  NULL);

-- ── RIDERS ─────────────────────────────────────────────────────
INSERT INTO RIDERS (user_id, avg_rating, wallet_balance) VALUES
(8,  4.90, 500.00),
(9,  4.70, 1200.00),
(10, 4.50, 250.00),
(11, 4.80, 750.00),
(12, 4.60, 100.00);

-- ── VEHICLES ───────────────────────────────────────────────────
INSERT INTO VEHICLES (make, model, year_, color, plate, type_, verif_st) VALUES
('Toyota',  'Corolla',  2020, 'White',  'ABC-123', 'sedan',    'verified'),
('Honda',   'Civic',    2021, 'Silver', 'DEF-456', 'sedan',    'verified'),
('Suzuki',  'Alto',     2019, 'Red',    'GHI-789', 'sedan',    'verified'),
('Toyota',  'Fortuner', 2022, 'Black',  'JKL-012', 'suv',      'verified'),
('Honda',   'CD-70',    2021, 'Black',  'MNO-345', 'bike',     'verified'),
('Suzuki',  'Carry',    2018, 'White',  'PQR-678', 'van',      'verified'),
('Rickshaw','CNG-Rikshaw',2017,'Yellow','STU-901', 'rickshaw', 'pending');

-- ── OWNS ───────────────────────────────────────────────────────
INSERT INTO OWNS (user_id, veh_id) VALUES
(3, 1),  -- Ahmed → Corolla
(3, 4),  -- Ahmed → Fortuner (owns two)
(4, 2),  -- Bilal → Civic
(5, 3),  -- Usman → Alto
(6, 5),  -- Zubair → Bike
(7, 7);  -- Faisal → Rickshaw

-- ── FARE RULES ─────────────────────────────────────────────────
INSERT INTO FARE_RULES (v_type, base_rate, km_rate, min_rate, surge, active) VALUES
('sedan',    80.00, 25.00, 100.00, 1.00, 1),
('suv',     120.00, 35.00, 150.00, 1.00, 1),
('bike',     40.00, 12.00,  60.00, 1.00, 1),
('van',     150.00, 40.00, 200.00, 1.00, 1),
('rickshaw', 40.00, 10.00,  50.00, 1.00, 1),
('other',    60.00, 18.00,  80.00, 1.00, 1);

-- ── PROMO CODES ────────────────────────────────────────────────
INSERT INTO PROMO_CODES (code, disc_pct, disc_amt, count, exp_date, active, `limit`) VALUES
('WELCOME20', 20.00, NULL,  0, DATE_ADD(CURDATE(), INTERVAL 90 DAY), 1, 1000),
('FLAT50',    NULL, 50.00,  3, DATE_ADD(CURDATE(), INTERVAL 30 DAY), 1, 200),
('EID2026',   15.00, NULL,  0, DATE_ADD(CURDATE(), INTERVAL 15 DAY), 1, 500),
('EXPIRED10', 10.00, NULL, 50, DATE_SUB(CURDATE(), INTERVAL 5 DAY),  0, 50);

-- ── RIDES ──────────────────────────────────────────────────────
INSERT INTO RIDES (rider_id, driver_id, veh_id, pickup, dropoff, city, status, fare, dist_km, req_at) VALUES
-- Completed rides
(8,  3, 1, 'F-6 Markaz, Islamabad',        'Blue Area, Islamabad',      'Islamabad', 'completed', 285.00, 8.2,  DATE_SUB(NOW(), INTERVAL 5 DAY)),
(9,  4, 2, 'Bahria Town, Islamabad',        'NUST University, H-12',     'Islamabad', 'completed', 420.00, 14.0, DATE_SUB(NOW(), INTERVAL 4 DAY)),
(10, 3, 4, 'F-10 Markaz, Islamabad',       'Centaurus Mall, Islamabad',  'Islamabad', 'completed', 310.00, 7.5,  DATE_SUB(NOW(), INTERVAL 3 DAY)),
(11, 4, 2, 'I-8 Markaz, Islamabad',        'Rawalpindi Saddar',          'Islamabad', 'completed', 520.00, 18.0, DATE_SUB(NOW(), INTERVAL 2 DAY)),
(8,  3, 1, 'Gulberg III, Lahore',          'Liberty Market, Lahore',     'Lahore',    'completed', 180.00, 5.0,  DATE_SUB(NOW(), INTERVAL 1 DAY)),
(12, 5, 3, 'Model Town, Lahore',           'Packages Mall, Lahore',      'Lahore',    'completed', 150.00, 4.2,  DATE_SUB(NOW(), INTERVAL 1 DAY)),
(9,  4, 2, 'DHA Phase 2, Islamabad',       'Islamabad Airport',          'Islamabad', 'completed', 650.00, 22.0, DATE_SUB(NOW(), INTERVAL 6 HOUR)),
-- Requested/Active rides
(10, NULL, NULL, 'Saddar, Rawalpindi',      'Raja Bazar, Rawalpindi',     'Islamabad', 'requested', NULL, NULL, NOW()),
(11, 3,    1,    'G-9 Markaz, Islamabad',   'Fatima Jinnah University',   'Islamabad', 'accepted',  NULL, NULL, DATE_SUB(NOW(), INTERVAL 10 MINUTE)),
-- Cancelled
(12, NULL, NULL, 'Johar Town, Lahore',      'MM Alam Road, Lahore',       'Lahore',    'cancelled', NULL, NULL, DATE_SUB(NOW(), INTERVAL 12 HOUR));

-- ── PAYMENTS ───────────────────────────────────────────────────
INSERT INTO PAYMENTS (ride_id, amount, method, status, date, discount) VALUES
(1, 285.00, 'cash',   'completed', DATE_SUB(NOW(), INTERVAL 5 DAY), 0.00),
(2, 420.00, 'card',   'completed', DATE_SUB(NOW(), INTERVAL 4 DAY), 0.00),
(3, 260.50, 'wallet', 'completed', DATE_SUB(NOW(), INTERVAL 3 DAY), 49.50),  -- promo applied
(4, 520.00, 'online', 'completed', DATE_SUB(NOW(), INTERVAL 2 DAY), 0.00),
(5, 144.00, 'wallet', 'completed', DATE_SUB(NOW(), INTERVAL 1 DAY), 36.00),  -- WELCOME20
(6, 150.00, 'cash',   'completed', DATE_SUB(NOW(), INTERVAL 1 DAY), 0.00),
(7, 600.00, 'card',   'completed', DATE_SUB(NOW(), INTERVAL 6 HOUR), 50.00); -- FLAT50

-- ── APPLIES (Promo used on payments) ───────────────────────────
INSERT INTO APPLIES (pay_id, promo_id) VALUES
(3, 1),  -- WELCOME20 on payment 3
(5, 1),  -- WELCOME20 on payment 5
(7, 2);  -- FLAT50 on payment 7

-- ── RIDE HISTORY ───────────────────────────────────────────────
INSERT INTO RIDE_HISTORY (ride_id, status, archived) VALUES
(1, 'completed', 0),
(2, 'completed', 0),
(3, 'completed', 0),
(4, 'completed', 0),
(5, 'completed', 0),
(6, 'completed', 0),
(7, 'completed', 0),
(10,'cancelled', 0);

-- ── DRIVER EARNINGS ────────────────────────────────────────────
INSERT INTO DRIVER_EARNINGS (driver_id, ride_id, gross, comm_pct, net, payout_st) VALUES
(3, 1, 285.00, 20.00, 228.00, 'paid'),
(4, 2, 420.00, 20.00, 336.00, 'paid'),
(3, 3, 310.00, 20.00, 248.00, 'pending'),
(4, 4, 520.00, 20.00, 416.00, 'pending'),
(3, 5, 180.00, 20.00, 144.00, 'pending'),
(5, 6, 150.00, 20.00, 120.00, 'pending'),
(4, 7, 650.00, 20.00, 520.00, 'pending');

-- ── RATINGS ────────────────────────────────────────────────────
INSERT INTO RATINGS (ride_id, rater_id, score, comment) VALUES
(1, 8,  5, 'Excellent driver, very polite!'),
(1, 3,  5, 'Good rider, on time.'),
(2, 9,  5, 'Smooth ride, AC was nice.'),
(2, 4,  4, 'Friendly but slight delay at pickup.'),
(3, 10, 4, 'Comfortable SUV, worth it.'),
(4, 11, 5, 'Professional driver.'),
(4, 4,  5, 'Great passenger.'),
(5, 8,  5, 'Quick ride!'),
(6, 12, 4, 'Good drive overall.');

-- ── ADMIN NOTIFICATIONS ────────────────────────────────────────
INSERT INTO ADMIN_NOTIFICATIONS (message, driver_id, is_read) VALUES
('New driver Faisal Mehmood requires vehicle verification.', 7, 0),
('Promo code EXPIRED10 has expired and been deactivated.', NULL, 1);

-- ── COMPLAINTS ─────────────────────────────────────────────────
INSERT INTO COMPLAINTS (ride_id, user_id, subject, description, status) VALUES
(2, 9, 'Driver took wrong route', 'The driver took a longer route increasing the fare.', 'in_review'),
(NULL, 10, 'App issue', 'Could not see driver location during ride.', 'open');
