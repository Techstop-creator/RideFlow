# 🚗 RideFlow — Database Systems Lab Project
**Spring 2026 | Irtaza Shahid (24i-0104) & Subhan Ahmad (24i-2613)**

---

## 📁 Project Structure

```
rideflow/
├── database/
│   ├── schema.sql        ← Full schema: tables, indexes, views, procedures, triggers, events, DCL
│   └── seed.sql          ← Raw SQL sample data (alternative to seed.js)
├── backend/
│   ├── server.js         ← Express.js REST API (all routes)
│   ├── db.js             ← MySQL connection pool
│   ├── seed.js           ← Node.js seeder (bcrypt-hashed passwords)
│   ├── package.json
│   └── .env.example      ← Copy to .env and fill in your DB credentials
└── frontend/
    ├── index.html        ← Login / Register page
    ├── rider.html        ← Rider Dashboard
    ├── driver.html       ← Driver Dashboard
    └── admin.html        ← Admin Panel (analytics + management)
```

---

## ⚙️ Setup Instructions

### Prerequisites
- **MySQL 8.0+** (with Event Scheduler enabled)
- **Node.js 18+**
- A terminal / command prompt

---

### Step 1 — Database Setup

Open MySQL Workbench or MySQL CLI and run:

```sql
SOURCE /path/to/rideflow/database/schema.sql;
```

This creates:
- All **14 tables** (D2 schema + extensions)
- **3 Views** (ActiveRidesView, TopDriversView, FullTripReportView)
- **4 Stored Procedures** (CalculateFare, CompleteRide, GetRevenueByCity, GetDriverStats)
- **4 Triggers** (payment→complete, rating→flag driver, promo count, cancel→archive)
- **2 Events** (nightly promo expiry, weekly archive)
- **DCL** (4 MySQL users with GRANT/REVOKE)
- **8 Indexes** (rider_id, driver_id, status, city, etc.)

---

### Step 2 — Backend Setup

```bash
cd rideflow/backend

# Install dependencies
npm install

# Create environment file
cp .env.example .env
```

Edit `.env`:
```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=YOUR_MYSQL_ROOT_PASSWORD
DB_NAME=ride_sharing
JWT_SECRET=rideflow_super_secret_jwt_key_2026
PORT=5000
```

---

### Step 3 — Seed Sample Data

```bash
node seed.js
```

This inserts 12 users, 5 drivers, 5 riders, 7 vehicles, 10 rides, payments, ratings, promo codes, and earnings with **properly bcrypt-hashed passwords**.

**Demo Login Credentials (all passwords: `password123`)**

| Role   | Email                | Password    |
|--------|----------------------|-------------|
| Admin  | admin@rideflow.pk    | password123 |
| Rider  | sara@rider.pk        | password123 |
| Rider  | ayesha@rider.pk      | password123 |
| Driver | ahmed@driver.pk      | password123 |
| Driver | bilal@driver.pk      | password123 |

---

### Step 4 — Start the Server

```bash
npm start
```

The server runs on **http://localhost:5000**

---

### Step 5 — Open the App

Open your browser and navigate to:

| Page          | URL                                      |
|---------------|------------------------------------------|
| Login         | http://localhost:5000                    |
| Rider         | http://localhost:5000/rider.html         |
| Driver        | http://localhost:5000/driver.html        |
| Admin Panel   | http://localhost:5000/admin.html         |

---

## ✅ Rubric Coverage Checklist

### D1 — ERD (20 marks) ✅
All 14 entities with relationships, cardinality, PKs, FKs, and attributes shown.

### D2 — Schema Conversion (30 marks) ✅
Full DDL in `schema.sql`:
- All constraints: NOT NULL, UNIQUE, CHECK, DEFAULT, FOREIGN KEY
- Correct data types (ENUM, DECIMAL, TINYINT, VARCHAR, DATE, DATETIME, YEAR)
- M:N resolved via junction tables: OWNS, APPLIES
- Referential integrity with ON DELETE / ON UPDATE actions

### D3 — Complete Implementation (100 marks)

#### 1. Basic SQL Queries (5 marks) ✅
- `GET /api/rider/rides` → Completed rides for specific rider, ordered by `req_at DESC`
- `GET /api/driver/rides/pending` → Drivers in a city ordered by rating

#### 2. Aggregate Functions & HAVING (10 marks) ✅
- `GET /api/admin/reports/revenue` → `SUM(amount)` grouped by city
- `GET /api/admin/reports/drivers` → `AVG(score)` with `HAVING AVG(score) < 3.5`
- `GET /api/admin/reports/drivers` → `COUNT(ride_id)` per driver with `GROUP BY`

#### 3. Joins for Reports (20 marks) ✅
- **INNER JOIN** in `FullTripReportView` → Riders ⋈ Rides ⋈ Drivers ⋈ Vehicles ⋈ Payments
- **LEFT JOIN** in riders report → All riders including those with 0 rides
- **JOIN Payments + PromoCodes** via APPLIES → Discount usage report

#### 4. Views, Indexes & Stored Procedures (15 marks) ✅
- `ActiveRidesView` — all ongoing trips with full rider/driver details
- `TopDriversView` — drivers with avg_rating ≥ 4.5
- `FullTripReportView` — complete trip report
- Indexes on: `rider_id`, `driver_id`, `status`, `city`, `req_at`
- `CalculateFare(ride_id, dist_km)` — auto-calculates fare with surge
- `CompleteRide(ride_id, dist_km, comm_pct)` — completes ride + earnings
- `GetRevenueByCity(start, end)` — revenue aggregation
- `GetDriverStats()` — driver performance summary

#### 5. Triggers & Events (10 marks) ✅
- `after_payment_completed` → Updates ride status + archives to RIDE_HISTORY
- `after_rating_insert` → Updates driver avg_rating, flags if < 3.5, notifies admin
- `after_promo_applied` → Increments promo usage count, auto-deactivates at limit
- `after_ride_cancelled` → Archives cancelled ride, frees driver
- Event: `expire_promo_codes` → Runs every night at midnight
- Event: `auto_archive_old_rides` → Archives rides older than 30 days weekly

#### 6. DCL — Hierarchical Access (10 marks) ✅
| Role         | Permissions                                              |
|--------------|----------------------------------------------------------|
| rider_app    | SELECT/INSERT on RIDES, PAYMENTS, RATINGS, RIDERS, PROMOS|
| driver_app   | SELECT on RIDES; SELECT/UPDATE on DRIVERS, EARNINGS      |
| admin_app    | ALL PRIVILEGES on ride_sharing.*                         |
| support_app  | SELECT only; REVOKE DELETE on critical tables            |

#### 7. User Interface (30 marks) ✅
- **Rider Dashboard**: Book ride, active ride tracker, history, wallet top-up, promo codes, rate driver
- **Driver Dashboard**: Toggle online/offline, accept/reject rides, start/complete rides, earnings history
- **Admin Panel**: User management, vehicle verification, fare rule editor, promo code creator, live analytics charts, 4 report types, views for active rides and top drivers
- Role-based login enforced (JWT tokens)
- All data from live MySQL database (no mock data)
- Analytics charts powered by Chart.js

---

## 🗃️ Database Tables (14 total)

| Table              | Purpose                              |
|--------------------|--------------------------------------|
| USERS              | Supertype for all user roles         |
| RIDERS             | Rider-specific data + wallet         |
| DRIVERS            | Driver profile, city, ratings        |
| ADMINS             | Admin with super flag                |
| VEHICLES           | Vehicle registration                 |
| OWNS               | Driver ↔ Vehicle (M:N junction)      |
| FARE_RULES         | Pricing per vehicle type with surge  |
| PROMO_CODES        | Discount codes with limits           |
| RIDES              | Core ride lifecycle table            |
| PAYMENTS           | Payment records per ride             |
| APPLIES            | Payment ↔ PromoCode (M:N junction)   |
| RIDE_HISTORY       | Archived completed/cancelled rides   |
| DRIVER_EARNINGS    | Net earnings per ride per driver     |
| RATINGS            | Mutual rider/driver ratings          |
| ADMIN_NOTIFICATIONS| Trigger-generated admin alerts       |
| COMPLAINTS         | User-submitted complaints            |

---

## 🔌 API Endpoints (60+ routes)

### Auth
- `POST /api/auth/login` — Returns JWT token
- `POST /api/auth/register` — Register rider or driver

### Rider (JWT required, role=rider)
- `GET  /api/rider/rides` — Ride history
- `POST /api/rider/rides/book` — Book a ride
- `PUT  /api/rider/rides/:id/cancel` — Cancel ride
- `POST /api/rider/payment` — Pay for completed ride
- `POST /api/rider/rating` — Rate the driver
- `GET  /api/rider/wallet` — Wallet balance + history
- `PUT  /api/rider/wallet/topup` — Top up wallet
- `GET  /api/rider/promo/:code` — Validate promo

### Driver (JWT required, role=driver)
- `PUT  /api/driver/status` — Toggle online/offline
- `GET  /api/driver/rides/pending` — Available ride requests
- `PUT  /api/driver/rides/:id/accept` — Accept a ride
- `PUT  /api/driver/rides/:id/start` — Start the trip
- `PUT  /api/driver/rides/:id/complete` — Complete + calculate fare (calls stored procedure)
- `GET  /api/driver/earnings` — Earnings history + summary

### Admin (JWT required, role=admin)
- `GET  /api/admin/dashboard` — Platform stats
- `GET  /api/admin/users` — User list with filters
- `PUT  /api/admin/users/:id/status` — Suspend/activate user
- `GET  /api/admin/vehicles` — All vehicles
- `PUT  /api/admin/vehicles/:id/status` — Verify/reject vehicle
- `GET  /api/admin/rides` — All rides (FullTripReportView)
- `GET  /api/admin/fare-rules` — Get fare configuration
- `PUT  /api/admin/fare-rules/:id` — Update fare rule
- `POST /api/admin/promos` — Create promo code
- `GET  /api/admin/reports/revenue` — Revenue by city + daily
- `GET  /api/admin/reports/drivers` — Driver stats + low-rated (HAVING)
- `GET  /api/admin/reports/riders` — All riders LEFT JOIN
- `GET  /api/admin/reports/promos` — Promo usage JOIN
- `GET  /api/admin/views/active-rides` — Query ActiveRidesView
- `GET  /api/admin/views/top-drivers` — Query TopDriversView
- `GET  /api/admin/notifications` — Admin alerts from triggers
