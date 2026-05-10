require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const bcrypt     = require('bcryptjs');
const jwt        = require('jsonwebtoken');
const path       = require('path');
const pool       = require('./db');

const app  = express();
const PORT = process.env.PORT || 5000;
const JWT_SECRET = process.env.JWT_SECRET || 'rideflow_jwt_secret_2026';

app.use(cors());
app.use(express.json());

// Serve frontend static files
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// ================================================================
// MIDDLEWARE: JWT Authentication
// ================================================================
const auth = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token provided' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
};

const role = (...roles) => (req, res, next) => {
  if (!roles.includes(req.user.role))
    return res.status(403).json({ error: 'Access denied for your role' });
  next();
};

// ================================================================
// AUTH ROUTES
// ================================================================

// POST /api/auth/login
app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password required' });
  try {
    const [users] = await pool.query(
      `SELECT u.user_id, u.full_name, u.email, u.phone, u.password, u.role, u.status
       FROM USERS u WHERE u.email = ?`, [email]
    );
    if (!users.length) return res.status(401).json({ error: 'Invalid email or password' });
    const user = users[0];
    if (user.status !== 'active') return res.status(403).json({ error: 'Account suspended or deleted' });
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.status(401).json({ error: 'Invalid email or password' });

    // Get role-specific data
    let extra = {};
    if (user.role === 'rider') {
      const [[r]] = await pool.query('SELECT wallet_balance, avg_rating FROM RIDERS WHERE user_id=?', [user.user_id]);
      extra = r || {};
    } else if (user.role === 'driver') {
      const [[d]] = await pool.query('SELECT avail_status, verif_status, avg_rating, city FROM DRIVERS WHERE user_id=?', [user.user_id]);
      extra = d || {};
    }

    const token = jwt.sign(
      { user_id: user.user_id, role: user.role, full_name: user.full_name },
      JWT_SECRET, { expiresIn: '24h' }
    );
    res.json({ token, user: { ...user, password: undefined, ...extra } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  }
});

// POST /api/auth/register
app.post('/api/auth/register', async (req, res) => {
  const { full_name, email, phone, password, role: userRole, license, cnic, city } = req.body;
  if (!full_name || !email || !phone || !password || !userRole)
    return res.status(400).json({ error: 'Missing required fields' });
  if (!['rider','driver'].includes(userRole))
    return res.status(400).json({ error: 'Can only self-register as rider or driver' });

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const hash = await bcrypt.hash(password, 10);
    const [result] = await conn.query(
      'INSERT INTO USERS (full_name, email, phone, password, role) VALUES (?,?,?,?,?)',
      [full_name, email, phone, hash, userRole]
    );
    const userId = result.insertId;
    if (userRole === 'rider') {
      await conn.query('INSERT INTO RIDERS (user_id) VALUES (?)', [userId]);
    } else if (userRole === 'driver') {
      if (!license || !cnic) {
        await conn.rollback();
        return res.status(400).json({ error: 'License and CNIC required for driver registration' });
      }
      await conn.query(
        'INSERT INTO DRIVERS (user_id, license, cnic, city) VALUES (?,?,?,?)',
        [userId, license, cnic, city || 'Islamabad']
      );
    }
    await conn.commit();
    res.status(201).json({ message: 'Account created successfully. Please log in.' });
  } catch (err) {
    await conn.rollback();
    if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ error: 'Email or phone already registered' });
    console.error(err);
    res.status(500).json({ error: 'Server error' });
  } finally {
    conn.release();
  }
});

// ================================================================
// RIDER ROUTES
// ================================================================

// GET /api/rider/profile
app.get('/api/rider/profile', auth, role('rider'), async (req, res) => {
  try {
    const [[user]] = await pool.query(
      `SELECT u.user_id, u.full_name, u.email, u.phone, u.status, u.created_at,
              ri.avg_rating, ri.wallet_balance, ri.reg_date
       FROM USERS u JOIN RIDERS ri ON u.user_id = ri.user_id
       WHERE u.user_id = ?`, [req.user.user_id]
    );
    res.json(user);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/rider/rides  — ride history for logged-in rider
app.get('/api/rider/rides', auth, role('rider'), async (req, res) => {
  try {
    // D3-Q1: List all completed rides for a specific rider ordered by date
    const [rides] = await pool.query(
      `SELECT r.ride_id, r.pickup, r.dropoff, r.city, r.status, r.fare, r.dist_km, r.req_at,
              u_d.full_name AS driver_name, u_d.phone AS driver_phone,
              v.make, v.model, v.plate, v.type_,
              p.amount, p.method, p.status AS pay_status, p.discount,
              rt.score AS my_rating
       FROM RIDES r
       LEFT JOIN USERS u_d    ON r.driver_id = u_d.user_id
       LEFT JOIN VEHICLES v   ON r.veh_id    = v.veh_id
       LEFT JOIN PAYMENTS p   ON r.ride_id   = p.ride_id
       LEFT JOIN RATINGS rt   ON r.ride_id   = rt.ride_id AND rt.rater_id = ?
       WHERE r.rider_id = ?
       ORDER BY r.req_at DESC`, [req.user.user_id, req.user.user_id]
    );
    res.json(rides);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/rider/rides/active  — current active ride
app.get('/api/rider/rides/active', auth, role('rider'), async (req, res) => {
  try {
    const [[ride]] = await pool.query(
      `SELECT r.*, u_d.full_name AS driver_name, u_d.phone AS driver_phone,
              d.avg_rating AS driver_rating,
              v.make, v.model, v.plate, v.color, v.type_
       FROM RIDES r
       LEFT JOIN USERS u_d  ON r.driver_id = u_d.user_id
       LEFT JOIN DRIVERS d  ON r.driver_id = d.user_id
       LEFT JOIN VEHICLES v ON r.veh_id    = v.veh_id
       WHERE r.rider_id = ? AND r.status IN ('requested','accepted','in_progress','waiting_payment')
       ORDER BY r.req_at DESC LIMIT 1`, [req.user.user_id]
    );
    res.json(ride || null);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// POST /api/rider/rides/book
app.post('/api/rider/rides/book', auth, role('rider'), async (req, res) => {
  const { pickup, dropoff, city, veh_type, sched_at } = req.body;
  if (!pickup || !dropoff) return res.status(400).json({ error: 'Pickup and dropoff required' });

  const conn = await pool.getConnection();
  try {
    // Check rider has no active ride
    const [[active]] = await conn.query(
      `SELECT ride_id FROM RIDES WHERE rider_id=? AND status IN ('requested','accepted','in_progress') LIMIT 1`,
      [req.user.user_id]
    );
    if (active) return res.status(409).json({ error: 'You already have an active ride' });

    const [result] = await conn.query(
      `INSERT INTO RIDES (rider_id, driver_id, veh_id, pickup, dropoff, city, status, sched_at)
       VALUES (?, NULL, NULL, ?, ?, ?, 'requested', ?)`,
      [req.user.user_id, pickup, dropoff, city || 'Islamabad', sched_at || null]
    );

    res.status(201).json({
      ride_id:   result.insertId,
      status:    'requested',
      driver:    null,
      message:   'Ride requested successfully! Searching for drivers...'
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  } finally {
    conn.release();
  }
});

// PUT /api/rider/rides/:id/cancel
app.put('/api/rider/rides/:id/cancel', auth, role('rider'), async (req, res) => {
  try {
    const [[ride]] = await pool.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND rider_id=?`,
      [req.params.id, req.user.user_id]
    );
    if (!ride) return res.status(404).json({ error: 'Ride not found' });
    if (!['requested','accepted'].includes(ride.status))
      return res.status(409).json({ error: 'Cannot cancel a ride in progress or already completed' });
    await pool.query(`UPDATE RIDES SET status='cancelled' WHERE ride_id=?`, [req.params.id]);
    res.json({ message: 'Ride cancelled' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// POST /api/rider/payment  — pay for a waiting ride
app.post('/api/rider/payment', auth, role('rider'), async (req, res) => {
  const { ride_id, method, promo_code, wallet_pin } = req.body;
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [[ride]] = await conn.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND rider_id=? AND status='waiting_payment'`,
      [ride_id, req.user.user_id]
    );
    if (!ride) return res.status(404).json({ error: 'Ride not found or not awaiting payment' });

    // Check if payment already exists
    const [[existingPay]] = await conn.query(`SELECT pay_id FROM PAYMENTS WHERE ride_id=?`, [ride_id]);
    if (existingPay) return res.status(409).json({ error: 'Payment already recorded for this ride' });

    let discount = 0;
    let promoId  = null;

    if (promo_code) {
      const [[promo]] = await conn.query(
        `SELECT * FROM PROMO_CODES WHERE code=? AND active=1 AND exp_date >= CURDATE()`, [promo_code]
      );
      if (promo) {
        discount  = promo.disc_pct ? (ride.fare * promo.disc_pct / 100) : promo.disc_amt;
        discount  = Math.min(discount, ride.fare);
        promoId   = promo.promo_id;
      }
    }

    const amount = Math.max(0, ride.fare - discount);

    // Deduct from wallet if method is wallet
    if (method === 'wallet') {
      const [[rider]] = await conn.query(`SELECT wallet_balance, wallet_pin FROM RIDERS WHERE user_id=?`, [req.user.user_id]);
      if (rider.wallet_pin !== wallet_pin) {
        await conn.rollback();
        return res.status(403).json({ error: 'Incorrect wallet PIN' });
      }
      if (rider.wallet_balance < amount) {
        await conn.rollback();
        return res.status(400).json({ error: 'Insufficient wallet balance' });
      }
      await conn.query(`UPDATE RIDERS SET wallet_balance = wallet_balance - ? WHERE user_id=?`,
        [amount, req.user.user_id]);
    }

    const [payResult] = await conn.query(
      `INSERT INTO PAYMENTS (ride_id, amount, method, status, discount) VALUES (?,?,?,'completed',?)`,
      [ride_id, amount, method, discount]
    );

    if (promoId) {
      await conn.query(`INSERT INTO APPLIES (pay_id, promo_id) VALUES (?,?)`, [payResult.insertId, promoId]);
    }

    // Now finalize the ride!
    await conn.query(`UPDATE RIDES SET status='completed' WHERE ride_id=?`, [ride_id]);
    await conn.query(`UPDATE DRIVERS SET avail_status='available' WHERE user_id=?`, [ride.driver_id]);

    const p_comm_pct = 20.00;
    const p_net_earn = ride.fare * (1 - p_comm_pct / 100);
    await conn.query(`INSERT IGNORE INTO DRIVER_EARNINGS (driver_id, ride_id, gross, comm_pct, net) VALUES (?,?,?,?,?)`,
      [ride.driver_id, ride_id, ride.fare, p_comm_pct, p_net_earn]);
    await conn.query(`INSERT INTO RIDE_HISTORY (ride_id, status) VALUES (?,'completed') ON DUPLICATE KEY UPDATE status='completed', arch_at=NOW()`, [ride_id]);

    await conn.commit();
    res.json({ message: 'Payment successful', pay_id: payResult.insertId, amount, discount });
  } catch (err) {
    await conn.rollback();
    res.status(500).json({ error: err.message });
  } finally {
    conn.release();
  }
});

// POST /api/rider/rating
app.post('/api/rider/rating', auth, role('rider'), async (req, res) => {
  const { ride_id, score, comment } = req.body;
  try {
    const [[ride]] = await pool.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND rider_id=? AND status='completed'`,
      [ride_id, req.user.user_id]
    );
    if (!ride) return res.status(404).json({ error: 'Ride not found or not completed' });
    await pool.query(
      `INSERT INTO RATINGS (ride_id, rater_id, score, comment) VALUES (?,?,?,?)
       ON DUPLICATE KEY UPDATE score=VALUES(score), comment=VALUES(comment)`,
      [ride_id, req.user.user_id, score, comment || null]
    );
    res.json({ message: 'Rating submitted' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/rider/promo/:code  — validate promo code
app.get('/api/rider/promo/:code', auth, role('rider'), async (req, res) => {
  try {
    const [[promo]] = await pool.query(
      `SELECT promo_id, code, disc_pct, disc_amt, exp_date, \`limit\`, count
       FROM PROMO_CODES WHERE code=? AND active=1 AND exp_date >= CURDATE()`,
      [req.params.code]
    );
    if (!promo) return res.status(404).json({ error: 'Invalid or expired promo code' });
    res.json(promo);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/rider/wallet
app.get('/api/rider/wallet', auth, role('rider'), async (req, res) => {
  try {
    const [[rider]] = await pool.query(`SELECT wallet_balance FROM RIDERS WHERE user_id=?`, [req.user.user_id]);
    const [txns] = await pool.query(
      `SELECT p.pay_id, p.amount, p.method, p.status, p.date, p.discount, r.pickup, r.dropoff
       FROM PAYMENTS p JOIN RIDES r ON p.ride_id = r.ride_id
       WHERE r.rider_id = ? ORDER BY p.date DESC LIMIT 20`, [req.user.user_id]
    );
    res.json({ balance: rider?.wallet_balance || 0, transactions: txns });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/rider/wallet/topup
app.put('/api/rider/wallet/topup', auth, role('rider'), async (req, res) => {
  const { amount } = req.body;
  if (!amount || amount <= 0) return res.status(400).json({ error: 'Invalid top-up amount' });
  try {
    await pool.query(`UPDATE RIDERS SET wallet_balance = wallet_balance + ? WHERE user_id=?`,
      [amount, req.user.user_id]);
    const [[r]] = await pool.query(`SELECT wallet_balance FROM RIDERS WHERE user_id=?`, [req.user.user_id]);
    res.json({ message: 'Wallet topped up', new_balance: r.wallet_balance });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ================================================================
// DRIVER ROUTES
// ================================================================

// GET /api/driver/profile
app.get('/api/driver/profile', auth, role('driver'), async (req, res) => {
  try {
    const [[driver]] = await pool.query(
      `SELECT u.user_id, u.full_name, u.email, u.phone, u.status, u.created_at,
              d.license, d.cnic, d.city, d.avail_status, d.verif_status, d.avg_rating
       FROM USERS u JOIN DRIVERS d ON u.user_id = d.user_id
       WHERE u.user_id = ?`, [req.user.user_id]
    );
    const [vehicles] = await pool.query(
      `SELECT v.* FROM VEHICLES v JOIN OWNS o ON v.veh_id = o.veh_id WHERE o.user_id=?`,
      [req.user.user_id]
    );
    res.json({ ...driver, vehicles });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/driver/status
app.put('/api/driver/status', auth, role('driver'), async (req, res) => {
  const { status } = req.body;
  const valid = ['available','offline'];
  if (!valid.includes(status)) return res.status(400).json({ error: 'Status must be available or offline' });
  try {
    const [[driver]] = await pool.query('SELECT avail_status FROM DRIVERS WHERE user_id=?', [req.user.user_id]);
    if (driver.avail_status === 'on_trip') {
      return res.status(403).json({ error: 'You cannot change your status while on a trip' });
    }
    await pool.query(`UPDATE DRIVERS SET avail_status=? WHERE user_id=?`, [status, req.user.user_id]);
    res.json({ message: `Status updated to ${status}` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/driver/rides/pending  — all rides awaiting a driver in driver's city
app.get('/api/driver/rides/pending', auth, role('driver'), async (req, res) => {
  try {
    const [[driver]] = await pool.query(`SELECT city FROM DRIVERS WHERE user_id=?`, [req.user.user_id]);
    const [rides] = await pool.query(
      `SELECT r.ride_id, r.pickup, r.dropoff, r.city, r.status, r.req_at,
              u.full_name AS rider_name, u.phone AS rider_phone,
              ri.avg_rating AS rider_rating
       FROM RIDES r
       JOIN USERS u  ON r.rider_id = u.user_id
       JOIN RIDERS ri ON r.rider_id = ri.user_id
       WHERE r.status = 'requested' AND r.city = ?
       ORDER BY r.req_at ASC`, [driver?.city || 'Islamabad']
    );
    res.json(rides);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/driver/rides/current  — driver's current active ride
app.get('/api/driver/rides/current', auth, role('driver'), async (req, res) => {
  try {
    const [[ride]] = await pool.query(
      `SELECT r.*, u.full_name AS rider_name, u.phone AS rider_phone,
              v.make, v.model, v.plate, v.type_
       FROM RIDES r
       JOIN USERS u    ON r.rider_id = u.user_id
       LEFT JOIN VEHICLES v ON r.veh_id = v.veh_id
       WHERE r.driver_id=? AND r.status IN ('accepted','in_progress','waiting_payment')
       ORDER BY r.req_at DESC LIMIT 1`, [req.user.user_id]
    );
    res.json(ride || null);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/driver/rides/:id/accept
app.put('/api/driver/rides/:id/accept', auth, role('driver'), async (req, res) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // Check if driver is online
    const [[driver]] = await conn.query(`SELECT avail_status FROM DRIVERS WHERE user_id=?`, [req.user.user_id]);
    if (!driver || driver.avail_status !== 'available') {
      await conn.rollback(); return res.status(403).json({ error: 'You must go online to accept rides' });
    }

    const [[ride]] = await conn.query(`SELECT * FROM RIDES WHERE ride_id=? AND status='requested'`, [req.params.id]);
    if (!ride) { await conn.rollback(); return res.status(404).json({ error: 'Ride not available' }); }

    // Get driver's verified vehicle
    const [[veh]] = await conn.query(
      `SELECT o.veh_id FROM OWNS o JOIN VEHICLES v ON o.veh_id=v.veh_id
       WHERE o.user_id=? AND v.verif_st='verified' LIMIT 1`, [req.user.user_id]
    );
    if (!veh) { await conn.rollback(); return res.status(400).json({ error: 'No verified vehicle found' }); }

    await conn.query(
      `UPDATE RIDES SET driver_id=?, veh_id=?, status='accepted' WHERE ride_id=?`,
      [req.user.user_id, veh.veh_id, req.params.id]
    );
    await conn.query(`UPDATE DRIVERS SET avail_status='on_trip' WHERE user_id=?`, [req.user.user_id]);
    await conn.commit();
    res.json({ message: 'Ride accepted' });
  } catch (err) {
    await conn.rollback();
    res.status(500).json({ error: err.message });
  } finally { conn.release(); }
});

// PUT /api/driver/rides/:id/start
app.put('/api/driver/rides/:id/start', auth, role('driver'), async (req, res) => {
  try {
    const [[ride]] = await pool.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND driver_id=? AND status='accepted'`,
      [req.params.id, req.user.user_id]
    );
    if (!ride) return res.status(404).json({ error: 'Ride not found or not in accepted state' });
    await pool.query(`UPDATE RIDES SET status='in_progress' WHERE ride_id=?`, [req.params.id]);
    res.json({ message: 'Ride started' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/driver/rides/:id/complete  — uses stored procedure
app.put('/api/driver/rides/:id/complete', auth, role('driver'), async (req, res) => {
  const { dist_km, duration_mins } = req.body;
  if (!dist_km || dist_km <= 0) return res.status(400).json({ error: 'Distance required' });
  if (!duration_mins || duration_mins <= 0) return res.status(400).json({ error: 'Duration required' });
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[ride]] = await conn.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND driver_id=? AND status='in_progress'`,
      [req.params.id, req.user.user_id]
    );
    if (!ride) { await conn.rollback(); return res.status(404).json({ error: 'Ride not found or not in progress' }); }

    // Call stored procedure
    await conn.query('CALL CompleteRide(?, ?, ?, ?, @fare, @net)', [req.params.id, dist_km, duration_mins, 20.00]);
    const [[result]] = await conn.query('SELECT @fare AS fare, @net AS net');

    await conn.commit();
    res.json({
      message:  'Payment requested. Waiting for rider.',
      fare:     result.fare
    });
  } catch (err) {
    await conn.rollback();
    res.status(500).json({ error: err.message });
  } finally { conn.release(); }
});

// GET /api/driver/earnings
app.get('/api/driver/earnings', auth, role('driver'), async (req, res) => {
  try {
    const [earnings] = await pool.query(
      `SELECT de.earn_id, de.ride_id, de.gross, de.comm_pct, de.net, de.payout_st, de.earn_at,
              r.pickup, r.dropoff, r.dist_km, r.city
       FROM DRIVER_EARNINGS de JOIN RIDES r ON de.ride_id = r.ride_id
       WHERE de.driver_id=? ORDER BY de.earn_at DESC`, [req.user.user_id]
    );
    const [[summary]] = await pool.query(
      `SELECT COUNT(*) AS total_rides,
              COALESCE(SUM(gross),0) AS total_gross,
              COALESCE(SUM(net),0)   AS total_net,
              COALESCE(SUM(CASE WHEN payout_st='pending' THEN net ELSE 0 END),0) AS pending_payout
       FROM DRIVER_EARNINGS WHERE driver_id=?`, [req.user.user_id]
    );
    res.json({ earnings, summary });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// POST /api/driver/rating  — driver rates a rider
app.post('/api/driver/rating', auth, role('driver'), async (req, res) => {
  const { ride_id, score, comment } = req.body;
  try {
    const [[ride]] = await pool.query(
      `SELECT * FROM RIDES WHERE ride_id=? AND driver_id=? AND status='completed'`,
      [ride_id, req.user.user_id]
    );
    if (!ride) return res.status(404).json({ error: 'Ride not found or not completed' });
    await pool.query(
      `INSERT INTO RATINGS (ride_id, rater_id, score, comment) VALUES (?,?,?,?)
       ON DUPLICATE KEY UPDATE score=VALUES(score), comment=VALUES(comment)`,
      [ride_id, req.user.user_id, score, comment || null]
    );
    res.json({ message: 'Rating submitted' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ================================================================
// ADMIN ROUTES
// ================================================================

// GET /api/admin/dashboard  — summary stats
app.get('/api/admin/dashboard', auth, role('admin'), async (req, res) => {
  try {
    const [[stats]] = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM USERS WHERE status='active') AS active_users,
        (SELECT COUNT(*) FROM DRIVERS WHERE verif_status='verified') AS verified_drivers,
        (SELECT COUNT(*) FROM RIDES WHERE status='completed') AS completed_rides,
        (SELECT COUNT(*) FROM RIDES WHERE status IN ('requested','accepted','in_progress')) AS active_rides,
        (SELECT COALESCE(SUM(amount),0) FROM PAYMENTS WHERE status='completed') AS total_revenue,
        (SELECT COUNT(*) FROM ADMIN_NOTIFICATIONS WHERE is_read=0) AS unread_notifications,
        (SELECT COUNT(*) FROM COMPLAINTS WHERE status='open') AS open_complaints
    `);
    res.json(stats);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/users
app.get('/api/admin/users', auth, role('admin'), async (req, res) => {
  const { role: filterRole, status, search } = req.query;
  try {
    let q = `SELECT u.user_id, u.full_name, u.email, u.phone, u.role, u.status, u.created_at FROM USERS u WHERE 1=1`;
    const params = [];
    if (filterRole) { q += ' AND u.role=?'; params.push(filterRole); }
    if (status)     { q += ' AND u.status=?'; params.push(status); }
    if (search)     { q += ' AND (u.full_name LIKE ? OR u.email LIKE ?)'; params.push(`%${search}%`, `%${search}%`); }
    q += ' ORDER BY u.created_at DESC';
    const [users] = await pool.query(q, params);
    res.json(users);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/admin/users/:id/status
app.put('/api/admin/users/:id/status', auth, role('admin'), async (req, res) => {
  const { status } = req.body;
  if (!['active','suspended','deleted'].includes(status))
    return res.status(400).json({ error: 'Invalid status' });
  try {
    if (status === 'suspended') {
      await pool.query('CALL SuspendUser(?, ?)', [req.user.user_id, req.params.id]);
    } else {
      await pool.query(`UPDATE USERS SET status=? WHERE user_id=?`, [status, req.params.id]);
    }
    res.json({ message: `User status updated to ${status}` });
  } catch (err) { 
    if (err.sqlState === '45000') {
      return res.status(403).json({ error: err.message });
    }
    res.status(500).json({ error: err.message }); 
  }
});

// GET /api/admin/vehicles
app.get('/api/admin/vehicles', auth, role('admin'), async (req, res) => {
  try {
    const [vehicles] = await pool.query(
      `SELECT v.*, u.full_name AS owner_name, u.phone AS owner_phone, u.email AS owner_email
       FROM VEHICLES v
       JOIN OWNS o ON v.veh_id = o.veh_id
       JOIN USERS u ON o.user_id = u.user_id
       ORDER BY v.veh_id DESC`
    );
    res.json(vehicles);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/admin/vehicles/:id/status
app.put('/api/admin/vehicles/:id/status', auth, role('admin'), async (req, res) => {
  const { verif_st } = req.body;
  if (!['pending','verified','rejected'].includes(verif_st))
    return res.status(400).json({ error: 'Invalid status' });
  try {
    await pool.query(`UPDATE VEHICLES SET verif_st=? WHERE veh_id=?`, [verif_st, req.params.id]);
    res.json({ message: `Vehicle status updated to ${verif_st}` });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/rides
app.get('/api/admin/rides', auth, role('admin'), async (req, res) => {
  const { status, city } = req.query;
  try {
    // D3-Q6: INNER JOIN full trip report
    let q = `SELECT * FROM FullTripReportView WHERE 1=1`;
    const params = [];
    if (status) { q += ' AND status=?';  params.push(status); }
    if (city)   { q += ' AND city=?';    params.push(city); }
    q += ' ORDER BY req_at DESC LIMIT 100';
    const [rides] = await pool.query(q, params);
    res.json(rides);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/fare-rules
app.get('/api/admin/fare-rules', auth, role('admin'), async (req, res) => {
  try {
    const [rules] = await pool.query('SELECT * FROM FARE_RULES ORDER BY v_type');
    res.json(rules);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/admin/fare-rules/:id
app.put('/api/admin/fare-rules/:id', auth, role('admin'), async (req, res) => {
  const { base_rate, km_rate, min_rate, surge, active } = req.body;
  try {
    await pool.query(
      `UPDATE FARE_RULES SET base_rate=?, km_rate=?, min_rate=?, surge=?, active=? WHERE rule_id=?`,
      [base_rate, km_rate, min_rate, surge, active, req.params.id]
    );
    res.json({ message: 'Fare rule updated' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/promos
app.get('/api/admin/promos', auth, role('admin'), async (req, res) => {
  try {
    const [promos] = await pool.query('SELECT * FROM PROMO_CODES ORDER BY promo_id DESC');
    res.json(promos);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// POST /api/admin/promos
app.post('/api/admin/promos', auth, role('admin'), async (req, res) => {
  const { code, disc_pct, disc_amt, exp_date, limit: lim } = req.body;
  try {
    await pool.query(
      `INSERT INTO PROMO_CODES (code, disc_pct, disc_amt, exp_date, \`limit\`) VALUES (?,?,?,?,?)`,
      [code, disc_pct || null, disc_amt || null, exp_date, lim || 100]
    );
    res.status(201).json({ message: 'Promo code created' });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ error: 'Promo code already exists' });
    res.status(500).json({ error: err.message });
  }
});

// GET /api/admin/reports/revenue  — D3-Q3 + GetRevenueByCity procedure
app.get('/api/admin/reports/revenue', auth, role('admin'), async (req, res) => {
  const { start, end } = req.query;
  try {
    const startDate = start || new Date(Date.now() - 30*86400000).toISOString().slice(0,10);
    const endDate   = end   || new Date().toISOString().slice(0,10);
    await pool.query('CALL GetRevenueByCity(?,?)', [startDate, endDate]);
    const [cityRevenue] = await pool.query('CALL GetRevenueByCity(?,?)', [startDate, endDate]);

    // Daily revenue for chart
    const [dailyRevenue] = await pool.query(
      `SELECT DATE(p.date) AS day, SUM(p.amount) AS revenue, COUNT(*) AS rides
       FROM PAYMENTS p WHERE p.status='completed' AND DATE(p.date) BETWEEN ? AND ?
       GROUP BY DATE(p.date) ORDER BY day`, [startDate, endDate]
    );

    // Payment method breakdown
    const [byMethod] = await pool.query(
      `SELECT method, COUNT(*) AS count, SUM(amount) AS total
       FROM PAYMENTS WHERE status='completed' AND DATE(date) BETWEEN ? AND ?
       GROUP BY method`, [startDate, endDate]
    );

    res.json({ cityRevenue: cityRevenue[0], dailyRevenue, byMethod });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/reports/drivers  — D3-Q4, Q5
app.get('/api/admin/reports/drivers', auth, role('admin'), async (req, res) => {
  try {
    // D3-Q5: COUNT trips per driver with GROUP BY
    const [tripCounts] = await pool.query(
      `SELECT d.user_id, u.full_name, d.city, d.avg_rating,
              COUNT(r.ride_id) AS completed_trips,
              COALESCE(SUM(de.net), 0) AS total_earnings
       FROM DRIVERS d
       JOIN USERS u ON d.user_id = u.user_id
       LEFT JOIN RIDES r ON d.user_id = r.driver_id AND r.status='completed'
       LEFT JOIN DRIVER_EARNINGS de ON d.user_id = de.driver_id
       GROUP BY d.user_id, u.full_name, d.city, d.avg_rating
       ORDER BY completed_trips DESC`
    );

    // D3-Q4: Drivers with AVG rating < 3.5 (HAVING clause)
    const [lowRated] = await pool.query(
      `SELECT d.user_id, u.full_name, d.city,
              AVG(rt.score) AS avg_score,
              COUNT(rt.rating_id) AS rating_count
       FROM DRIVERS d
       JOIN USERS u ON d.user_id = u.user_id
       JOIN RIDES r ON d.user_id = r.driver_id
       JOIN RATINGS rt ON r.ride_id = rt.ride_id
       GROUP BY d.user_id, u.full_name, d.city
       HAVING AVG(rt.score) < 3.5
       ORDER BY avg_score ASC`
    );

    // Top drivers view
    const [topDrivers] = await pool.query('SELECT * FROM TopDriversView LIMIT 10');

    res.json({ tripCounts, lowRated, topDrivers });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/reports/riders  — D3-Q7 LEFT JOIN
app.get('/api/admin/reports/riders', auth, role('admin'), async (req, res) => {
  try {
    // D3-Q7: ALL riders including those with no rides (LEFT JOIN)
    const [riders] = await pool.query(
      `SELECT u.user_id, u.full_name, u.email, ri.wallet_balance, ri.avg_rating,
              COUNT(r.ride_id) AS total_rides,
              COALESCE(SUM(p.amount),0) AS total_spent
       FROM USERS u
       JOIN RIDERS ri ON u.user_id = ri.user_id
       LEFT JOIN RIDES r    ON u.user_id = r.rider_id AND r.status='completed'
       LEFT JOIN PAYMENTS p ON r.ride_id = p.ride_id AND p.status='completed'
       GROUP BY u.user_id, u.full_name, u.email, ri.wallet_balance, ri.avg_rating
       ORDER BY total_rides DESC`
    );
    res.json(riders);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/reports/promos  — D3-Q8 promo code usage
app.get('/api/admin/reports/promos', auth, role('admin'), async (req, res) => {
  try {
    const [promoUsage] = await pool.query(
      `SELECT r.ride_id, u.full_name AS rider_name, r.city,
              p.amount, p.discount, p.method,
              pc.code AS promo_code, pc.disc_pct, pc.disc_amt
       FROM PAYMENTS p
       JOIN RIDES r        ON p.ride_id   = r.ride_id
       JOIN USERS u        ON r.rider_id  = u.user_id
       JOIN APPLIES ap     ON p.pay_id    = ap.pay_id
       JOIN PROMO_CODES pc ON ap.promo_id = pc.promo_id
       ORDER BY p.date DESC`
    );
    res.json(promoUsage);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/views/active-rides  — ActiveRidesView
app.get('/api/admin/views/active-rides', auth, role('admin'), async (req, res) => {
  try {
    const [rides] = await pool.query('SELECT * FROM ActiveRidesView ORDER BY req_at DESC');
    res.json(rides);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/views/top-drivers  — TopDriversView
app.get('/api/admin/views/top-drivers', auth, role('admin'), async (req, res) => {
  try {
    const [drivers] = await pool.query('SELECT * FROM TopDriversView ORDER BY avg_rating DESC');
    res.json(drivers);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/notifications
app.get('/api/admin/notifications', auth, role('admin'), async (req, res) => {
  try {
    const [notifs] = await pool.query(
      `SELECT n.*, u.full_name AS driver_name
       FROM ADMIN_NOTIFICATIONS n
       LEFT JOIN USERS u ON n.driver_id = u.user_id
       ORDER BY n.created_at DESC LIMIT 50`
    );
    res.json(notifs);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/admin/notifications/:id/read
app.put('/api/admin/notifications/:id/read', auth, role('admin'), async (req, res) => {
  try {
    await pool.query('UPDATE ADMIN_NOTIFICATIONS SET is_read=1 WHERE notif_id=?', [req.params.id]);
    res.json({ message: 'Marked as read' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// GET /api/admin/complaints
app.get('/api/admin/complaints', auth, role('admin'), async (req, res) => {
  try {
    const [complaints] = await pool.query(
      `SELECT c.*, u.full_name AS user_name, u.email AS user_email
       FROM COMPLAINTS c JOIN USERS u ON c.user_id = u.user_id
       ORDER BY c.created_at DESC`
    );
    res.json(complaints);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// PUT /api/admin/complaints/:id/status
app.put('/api/admin/complaints/:id/status', auth, role('admin'), async (req, res) => {
  const { status } = req.body;
  try {
    await pool.query('UPDATE COMPLAINTS SET status=? WHERE comp_id=?', [status, req.params.id]);
    res.json({ message: 'Complaint status updated' });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// Catch-all: serve frontend
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`\n🚗 RideFlow server running on http://localhost:${PORT}`);
  console.log(`📊 Admin Panel: http://localhost:${PORT}/admin.html`);
  console.log(`🏠 Rider:       http://localhost:${PORT}/rider.html`);
  console.log(`🚘 Driver:      http://localhost:${PORT}/driver.html\n`);
});
