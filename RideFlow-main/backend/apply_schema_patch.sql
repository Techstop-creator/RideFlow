-- Update RIDES status enum
ALTER TABLE RIDES MODIFY COLUMN status ENUM('requested','accepted','en_route','in_progress','waiting_payment','completed','cancelled') NOT NULL DEFAULT 'requested';

-- Add wallet_pin to RIDERS
ALTER TABLE RIDERS ADD COLUMN wallet_pin VARCHAR(4) NOT NULL DEFAULT '1234';

-- Drop and recreate CompleteRide procedure
DROP PROCEDURE IF EXISTS CompleteRide;

DELIMITER $$
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

    -- Note: Net earnings and driver availability will be handled when the rider confirms payment
    SET p_net_earn = 0;
END$$
DELIMITER ;
