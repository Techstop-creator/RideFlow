require('dotenv').config();
const bcrypt = require('bcryptjs');
const pool   = require('./db');

const PASS = 'password123';
const COST = 10;

async function seed() {
  const conn = await pool.getConnection();
  try {
    const hash = await bcrypt.hash(PASS, COST);
    console.log('🔐 Password hash generated');

    await conn.beginTransaction();

    // Clear tables in reverse FK order
    const tables = [
      'COMPLAINTS','ADMIN_NOTIFICATIONS','RIDE_HISTORY',
      'DRIVER_EARNINGS','RATINGS','APPLIES','PAYMENTS',
      'RIDES','PROMO_CODES','FARE_RULES','OWNS','VEHICLES',
      'ADMINS','DRIVERS','RIDERS','USERS'
    ];
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');
    for (const t of tables) {
      await conn.query(`DELETE FROM ${t}`);
      if (['USERS','VEHICLES','RIDES','PAYMENTS','FARE_RULES',
           'PROMO_CODES','RATINGS','DRIVER_EARNINGS','ADMIN_NOTIFICATIONS',
           'COMPLAINTS','RIDE_HISTORY'].includes(t)) {
        await conn.query(`ALTER TABLE ${t} AUTO_INCREMENT = 1`);
      }
    }
    await conn.query('SET FOREIGN_KEY_CHECKS = 1');
    console.log('🗑️  Tables cleared');

    // USERS
    await conn.query(`
      INSERT INTO USERS (full_name, email, phone, password, role, status) VALUES
      ('Super Admin',   'admin@rideflow.pk',   '03001111111', ?, 'admin',  'active'),
      ('Support Admin', 'support@rideflow.pk', '03001111112', ?, 'admin',  'active'),
      ('Ahmed Raza',    'ahmed@driver.pk',     '03211234567', ?, 'driver', 'active'),
      ('Bilal Khan',    'bilal@driver.pk',     '03211234568', ?, 'driver', 'active'),
      ('Usman Tariq',   'usman@driver.pk',     '03211234569', ?, 'driver', 'active'),
      ('Zubair Ali',    'zubair@driver.pk',    '03211234570', ?, 'driver', 'active'),
      ('Faisal Mehmood','faisal@driver.pk',    '03211234571', ?, 'driver', 'active'),
      ('Sara Malik',    'sara@rider.pk',       '03331234567', ?, 'rider',  'active'),
      ('Ayesha Khan',   'ayesha@rider.pk',     '03331234568', ?, 'rider',  'active'),
      ('Hassan Iqbal',  'hassan@rider.pk',     '03331234569', ?, 'rider',  'active'),
      ('Fatima Zahra',  'fatima@rider.pk',     '03331234570', ?, 'rider',  'active'),
      ('Omar Siddiqui', 'omar@rider.pk',       '03331234571', ?, 'rider',  'active')
    `, Array(12).fill(hash));
    console.log('✅ Users inserted (12)');

    await conn.query(`INSERT INTO ADMINS (user_id, is_super) VALUES (1,1),(2,0)`);
    console.log('✅ Admins inserted');

    await conn.query(`
      INSERT INTO DRIVERS (user_id, license, cnic, city, avail_status, verif_status, avg_rating) VALUES
      (3,'LHR-2021-001','35201-1234567-1','Islamabad','available','verified',4.80),
      (4,'ISB-2022-002','35202-2345678-2','Islamabad','available','verified',4.60),
      (5,'KHI-2020-003','35203-3456789-3','Lahore',   'offline',  'verified',4.20),
      (6,'LHR-2019-004','35204-4567890-4','Islamabad','offline',  'verified',3.90),
      (7,'ISB-2023-005','35205-5678901-5','Karachi',  'available','pending', NULL)
    `);
    console.log('✅ Drivers inserted');

    await conn.query(`
      INSERT INTO RIDERS (user_id, avg_rating, wallet_balance, wallet_pin) VALUES
      (8, 4.90, 500.00, '1234'),
      (9, 4.70, 1200.00, '1234'),
      (10, 4.50, 250.00, '1234'),
      (11, 4.80, 750.00, '1234'),
      (12, 4.60, 100.00, '1234')
    `);
    console.log('✅ Riders inserted');

    await conn.query(`
      INSERT INTO VEHICLES (make, model, year_, color, plate, type_, verif_st) VALUES
      ('Toyota','Corolla',  2020,'White', 'ABC-123','sedan',   'verified'),
      ('Honda', 'Civic',    2021,'Silver','DEF-456','sedan',   'verified'),
      ('Suzuki','Alto',     2019,'Red',   'GHI-789','sedan',   'verified'),
      ('Toyota','Fortuner', 2022,'Black', 'JKL-012','suv',     'verified'),
      ('Honda', 'CD-70',    2021,'Black', 'MNO-345','bike',    'verified'),
      ('Suzuki','Carry',    2018,'White', 'PQR-678','van',     'verified'),
      ('Rickshaw','CNG',    2017,'Yellow','STU-901','rickshaw','pending')
    `);

    await conn.query(`
      INSERT INTO OWNS (user_id, veh_id) VALUES
      (3,1),(3,4),(4,2),(5,3),(6,5),(7,7)
    `);
    console.log('✅ Vehicles + Owns inserted');

    await conn.query(`
      INSERT INTO FARE_RULES (v_type, base_rate, km_rate, min_rate, per_min_rate, surge, active) VALUES
      ('sedan',  80.00,25.00,100.00, 5.00, 1.00,1),
      ('suv',   120.00,35.00,150.00, 7.00, 1.00,1),
      ('bike',   40.00,12.00, 60.00, 3.00, 1.00,1),
      ('van',   150.00,40.00,200.00, 8.00, 1.00,1),
      ('rickshaw',40.00,10.00,50.00, 2.00, 1.00,1),
      ('other',  60.00,18.00, 80.00, 4.00, 1.00,1)
    `);
    console.log('✅ Fare rules inserted');

    const futureDate  = new Date(); futureDate.setMonth(futureDate.getMonth() + 3);
    const future1     = futureDate.toISOString().slice(0, 10);
    const future2     = new Date(Date.now() + 30*86400000).toISOString().slice(0, 10);
    const future3     = new Date(Date.now() + 15*86400000).toISOString().slice(0, 10);
    const pastDate    = new Date(Date.now() - 5*86400000).toISOString().slice(0, 10);

    await conn.query(`
      INSERT INTO PROMO_CODES (code, disc_pct, disc_amt, count, exp_date, active, \`limit\`) VALUES
      ('WELCOME20', 20.00, NULL,  0, ?, 1, 1000),
      ('FLAT50',    NULL, 50.00,  3, ?, 1, 200),
      ('EID2026',   15.00, NULL,  0, ?, 1, 500),
      ('EXPIRED10', 10.00, NULL, 50, ?, 0, 50)
    `, [future1, future2, future3, pastDate]);
    console.log('✅ Promo codes inserted');

    // Rides with dates
    const now = new Date();
    const ago = (days, hours=0) => new Date(now - days*86400000 - hours*3600000).toISOString().slice(0,19).replace('T',' ');

    await conn.query(`
      INSERT INTO RIDES (rider_id, driver_id, veh_id, pickup, dropoff, city, status, fare, dist_km, req_at) VALUES
      (8, 3,1,'F-6 Markaz, Islamabad',     'Blue Area, Islamabad',       'Islamabad','completed',285.00, 8.2,'${ago(5)}'),
      (9, 4,2,'Bahria Town, Islamabad',    'NUST University, H-12',      'Islamabad','completed',420.00,14.0,'${ago(4)}'),
      (10,3,4,'F-10 Markaz, Islamabad',    'Centaurus Mall, Islamabad',  'Islamabad','completed',310.00, 7.5,'${ago(3)}'),
      (11,4,2,'I-8 Markaz, Islamabad',     'Rawalpindi Saddar',          'Islamabad','completed',520.00,18.0,'${ago(2)}'),
      (8, 3,1,'Gulberg III, Lahore',        'Liberty Market, Lahore',     'Lahore',   'completed',180.00, 5.0,'${ago(1)}'),
      (12,5,3,'Model Town, Lahore',         'Packages Mall, Lahore',      'Lahore',   'completed',150.00, 4.2,'${ago(1)}'),
      (9, 4,2,'DHA Phase 2, Islamabad',    'Islamabad Airport',           'Islamabad','completed',650.00,22.0,'${ago(0,6)}'),
      (10,NULL,NULL,'Saddar, Rawalpindi',  'Raja Bazar, Rawalpindi',      'Islamabad','requested',NULL,NULL,'${ago(0)}'),
      (11,3,1,'G-9 Markaz, Islamabad',     'Fatima Jinnah University',   'Islamabad','accepted', NULL,NULL,'${ago(0)}'),
      (12,NULL,NULL,'Johar Town, Lahore',  'MM Alam Road, Lahore',        'Lahore',   'cancelled',NULL,NULL,'${ago(0,12)}')
    `);
    console.log('✅ Rides inserted (10)');

    await conn.query(`
      INSERT INTO PAYMENTS (ride_id, amount, method, status, date, discount) VALUES
      (1,285.00,'cash',  'completed','${ago(5)}',0.00),
      (2,420.00,'card',  'completed','${ago(4)}',0.00),
      (3,260.50,'wallet','completed','${ago(3)}',49.50),
      (4,520.00,'online','completed','${ago(2)}',0.00),
      (5,144.00,'wallet','completed','${ago(1)}',36.00),
      (6,150.00,'cash',  'completed','${ago(1)}',0.00),
      (7,600.00,'card',  'completed','${ago(0,6)}',50.00)
    `);

    await conn.query(`
      INSERT INTO APPLIES (pay_id, promo_id) VALUES (3,1),(5,1),(7,2)
    `);
    console.log('✅ Payments + Applies inserted');

    await conn.query(`
      INSERT INTO RIDE_HISTORY (ride_id, status, archived) VALUES
      (1,'completed',0),(2,'completed',0),(3,'completed',0),
      (4,'completed',0),(5,'completed',0),(6,'completed',0),
      (7,'completed',0),(10,'cancelled',0)
    `);

    await conn.query(`
      INSERT INTO DRIVER_EARNINGS (driver_id, ride_id, gross, comm_pct, net, payout_st) VALUES
      (3,1,285.00,20.00,228.00,'paid'),
      (4,2,420.00,20.00,336.00,'paid'),
      (3,3,310.00,20.00,248.00,'pending'),
      (4,4,520.00,20.00,416.00,'pending'),
      (3,5,180.00,20.00,144.00,'pending'),
      (5,6,150.00,20.00,120.00,'pending'),
      (4,7,650.00,20.00,520.00,'pending')
    `);
    console.log('✅ Earnings inserted');

    await conn.query(`
      INSERT INTO RATINGS (ride_id, rater_id, score, comment) VALUES
      (1,8, 5,'Excellent driver, very polite!'),
      (1,3, 5,'Good rider, on time.'),
      (2,9, 5,'Smooth ride, AC was nice.'),
      (2,4, 4,'Friendly but slight delay at pickup.'),
      (3,10,4,'Comfortable SUV, worth it.'),
      (4,11,5,'Professional driver.'),
      (4,4, 5,'Great passenger.'),
      (5,8, 5,'Quick ride!'),
      (6,12,4,'Good drive overall.')
    `);

    await conn.query(`
      INSERT INTO ADMIN_NOTIFICATIONS (message, driver_id, is_read) VALUES
      ('New driver Faisal Mehmood requires vehicle verification.',7,0),
      ('Promo code EXPIRED10 has expired and been deactivated.',NULL,1)
    `);

    await conn.query(`
      INSERT INTO COMPLAINTS (ride_id, user_id, subject, description, status) VALUES
      (2,9,'Driver took wrong route','The driver took a longer route increasing the fare.','in_review'),
      (NULL,10,'App issue','Could not see driver location during ride.','open')
    `);

    await conn.commit();
    console.log('\n🎉 All seed data inserted successfully!');
    console.log('\n📋 Demo Login Credentials (all use password: password123)');
    console.log('─────────────────────────────────────────────');
    console.log('ADMIN:  admin@rideflow.pk   / password123');
    console.log('RIDER:  sara@rider.pk       / password123');
    console.log('DRIVER: ahmed@driver.pk     / password123');
    console.log('─────────────────────────────────────────────\n');
  } catch (err) {
    await conn.rollback();
    console.error('❌ Seed failed:', err.message);
    throw err;
  } finally {
    conn.release();
    process.exit(0);
  }
}

seed();
