INSERT INTO Supplier (name, contact_person, email, phone, address, city, state, country, active) VALUES
('KitchenTech Solutions', 'Emma Larson', 'emma.larson@kitchentech.com', '+1-555-123-4567', '123 Culinary Lane', 'Chicago', 'IL', 'USA', TRUE),
('ElectroMart Supplies', 'James Patel', 'james.patel@electromart.com', '+44-20-7890-1234', '456 Tech Road', 'London', NULL, 'UK', TRUE),
('FreshHarvest Foods', 'Maria Gonzalez', 'maria.gonzalez@freshharvest.com', '+1-408-987-6543', '789 Farm Street', 'Salinas', 'CA', 'USA', TRUE),
('PlumbPro Equipment', 'Liam O’Connor', 'liam.oconnor@plumbpro.com', '+61-2-8765-4321', '101 Pipe Avenue', 'Sydney', 'NSW', 'Australia', TRUE),
('ToolTrend Innovations', 'Sophie Kim', 'sophie.kim@tooltrend.com', '+1-303-555-7890', '321 Forge Boulevard', 'Denver', 'CO', 'USA', TRUE);


ALTER TABLE Products
ADD COLUMN image_path VARCHAR(255);
INSERT INTO Products (name, description, category, price, supplier_id, image_path) VALUES
-- Electronics (Supplier: ElectroMart Supplies, supplier_id: 2)
('Smartphone Y', 'Latest model with 128GB storage and 48MP camera', 'Electronics', 699.99, 2, '/images/smartphone_y.jpg'),
('Bluetooth Speaker', 'Portable speaker with 12-hour battery life', 'Electronics', 49.99, 2, '/images/bluetooth_speaker.jpg'),
('Smart Bulb', 'Wi-Fi enabled LED bulb with color-changing features', 'Electronics', 19.99, 2, '/images/smart_bulb.jpg'),
-- Food (Supplier: FreshHarvest Foods, supplier_id: 3)
('Organic Quinoa', '1kg pack of premium organic quinoa', 'Food', 8.49, 3, '/images/organic_quinoa.jpg'),
('Honey Jar', '500g jar of pure wildflower honey', 'Food', 12.99, 3, '/images/honey_jar.jpg'),
('Almond Butter', '250g jar of creamy almond butter, no added sugar', 'Food', 7.99, 3, '/images/almond_butter.jpg'),
-- Kitchen-ware (Supplier: KitchenTech Solutions, supplier_id: 1)
('Ceramic Mixing Bow', '5L ceramic mixing bowl, dishwasher safe', 'Kitchen-ware', 24.99, 1, '/images/ceramic_mixing_bow.jpg'),
('Chef''s Knife', '8-inch stainless steel chef''s knife with ergonomic handle', 'Kitchen-ware', 39.99, 1, '/images/chefs_knife.jpg'),
('Silicone Spatula', 'Heat-resistant silicone spatula, 12 inches', 'Kitchen-ware', 9.99, 1, '/images/silicone_spatula.jpg'),
-- Tools (Supplier: ToolTrend Innovations, supplier_id: 5)
('Claw Hammer', '16oz claw hammer with non-slip grip', 'Tools', 14.99, 5, '/images/claw_hammer.jpg'),
('Screw Set', '100-piece screw set for various applications', 'Tools', 12.49, 5, '/images/screw_set.jpg'),
('Tape Measure', '25ft tape measure with lock mechanism', 'Tools', 8.99, 5, '/images/tape_measure.jpg');
UPDATE Products
SET image_path = REPLACE(image_path, '.jpg', '.png');

INSERT INTO Inventory (product_id, quantity_in_stock, reorder_level, reserved_quantity) VALUES
-- Electronics (product_id 1-3)
(1, 50, 20, 5),    -- Smartphone Y: High-value item, moderate stock
(2, 150, 50, 10),   -- Bluetooth Speaker: Popular item, higher stock
(3, 300, 100, 20),  -- Smart Bulb: Smaller item, high stock
-- Food (product_id 4-6)
(4, 200, 50, 15),   -- Organic Quinoa: Bulk food item, decent stock
(5, 120, 30, 8),    -- Honey Jar: Specialty food, moderate stock
(6, 180, 40, 12),   -- Almond Butter: Similar to honey, slightly higher stock
-- Kitchen-ware (product_id 7-9)
(7, 80, 25, 5),     -- Ceramic Mixing Bow: Bulky item, moderate stock
(8, 60, 20, 3),     -- Chef's Knife: High-quality item, lower stock
(9, 250, 75, 10),   -- Silicone Spatula: Smaller, cheaper item, higher stock
-- Tools (product_id 10-12)
(10, 100, 30, 5),   -- Claw Hammer: Standard tool, moderate stock
(11, 500, 150, 25), -- Screw Set: Small items sold in bulk, high stock
(12, 200, 50, 10);  -- Tape Measure: Common tool, decent stock