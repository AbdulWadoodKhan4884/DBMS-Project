CREATE TYPE order_status AS ENUM (
    'cart', 
    'confirmed', 
    'processing', 
    'shipped', 
    'delivered', 
    'returned'
);

CREATE TYPE customer_tier AS ENUM ('regular', 'premium', 'vip');

CREATE TYPE payment_method AS ENUM (
    'COD', 
    'credit_card', 
    'debit_card', 
    'paypal', 
    'bank_transfer', 
    'digital_wallet'
);

CREATE TABLE Supplier (
    supplier_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    contact_person VARCHAR(100),
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20) NOT NULL,
    address TEXT NOT NULL,
    city VARCHAR(50) NOT NULL,
    state VARCHAR(50),
    country VARCHAR(50) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CHECK (email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$')
);

CREATE TABLE Products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    category VARCHAR(50) NOT NULL,
    price DECIMAL(10, 2) NOT NULL CHECK (price > 0),
    supplier_id INTEGER NOT NULL REFERENCES Supplier(supplier_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Inventory (
    inventory_id SERIAL PRIMARY KEY,
    product_id INTEGER UNIQUE NOT NULL REFERENCES Products(product_id) ON DELETE CASCADE,
    quantity_in_stock INTEGER NOT NULL CHECK (quantity_in_stock >= 0) DEFAULT 0,
    reorder_level INTEGER CHECK (reorder_level >= 0) DEFAULT 10,
    last_stock_update TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reserved_quantity INTEGER NOT NULL CHECK (reserved_quantity >= 0) DEFAULT 0
);

CREATE TABLE Customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    country VARCHAR(50),
    password_hash VARCHAR(255) NOT NULL,
    tier customer_tier DEFAULT 'regular',
    cart INTEGER[] DEFAULT '{}',
    orders INTEGER[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CHECK (email ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$')
);

CREATE TABLE Orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES Customers(customer_id),
    order_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    status order_status DEFAULT 'cart',
    payment_method payment_method,
    payment BOOLEAN DEFAULT FALSE,
    total_amount DECIMAL(12, 2) CHECK (total_amount >= 0),
    shipping_address TEXT NOT NULL,
    shipping_city VARCHAR(50) NOT NULL,
    shipping_state VARCHAR(50),
    shipping_country VARCHAR(50) NOT NULL,
    items INTEGER[] NOT NULL,
    quantities INTEGER[] NOT NULL,
    notes TEXT
);

CREATE OR REPLACE FUNCTION validate_order_quantities()
RETURNS TRIGGER AS $$
DECLARE
    arr_length INTEGER;
BEGIN
    -- Check if both arrays exist and have the same length
    IF NEW.items IS NULL OR NEW.quantities IS NULL THEN
        RAISE EXCEPTION 'Both items and quantities arrays must be provided';
    END IF;
    
    arr_length := array_length(NEW.items, 1);
    IF arr_length IS DISTINCT FROM array_length(NEW.quantities, 1) THEN
        RAISE EXCEPTION 'Items and quantities arrays must have the same length';
    END IF;
    
    -- Check all quantities are positive integers
    IF arr_length > 0 AND EXISTS (
        SELECT 1 FROM unnest(NEW.quantities) AS q 
        WHERE q <= 0
    ) THEN
        RAISE EXCEPTION 'All quantities must be positive numbers';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_order_quantities
BEFORE INSERT OR UPDATE ON Orders
FOR EACH ROW
EXECUTE FUNCTION validate_order_quantities();

CREATE OR REPLACE FUNCTION validate_order_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent invalid status transitions
    IF OLD.status IS NOT NULL AND NEW.status <> OLD.status THEN
        -- Cannot go back to cart from confirmed states
        IF OLD.status <> 'cart' AND NEW.status = 'cart' THEN
            RAISE EXCEPTION 'Cannot return order to cart status once progressed';
        END IF;
        
        -- Payment required before shipping
        IF NEW.status = 'shipped' AND NOT NEW.payment THEN
            RAISE EXCEPTION 'Cannot ship order without payment confirmation';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_order_status
BEFORE UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION validate_order_status();

-- Prevent negative inventory (absolute safeguard)
ALTER TABLE Inventory ADD CONSTRAINT non_negative_inventory
CHECK (quantity_in_stock >= 0 AND reserved_quantity >= 0);

-- Ensure reserved quantity doesn't exceed available stock
ALTER TABLE Inventory ADD CONSTRAINT valid_reserved_quantity
CHECK (reserved_quantity <= quantity_in_stock);

CREATE OR REPLACE FUNCTION validate_customer_orders()
RETURNS TRIGGER AS $$
DECLARE
    invalid_orders INTEGER[];
BEGIN
    -- Check if any order IDs don't exist in Orders table
    IF NEW.orders IS NOT NULL THEN
        SELECT array_agg(o) INTO invalid_orders
        FROM unnest(NEW.orders) o
        LEFT JOIN Orders ON Orders.order_id = o
        WHERE Orders.order_id IS NULL AND o IS NOT NULL;
        
        IF invalid_orders IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid order IDs in orders array: %', invalid_orders;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_customer_orders
BEFORE INSERT OR UPDATE OF orders ON Customers
FOR EACH ROW
EXECUTE FUNCTION validate_customer_orders();

CREATE OR REPLACE FUNCTION validate_customer_cart()
RETURNS TRIGGER AS $$
DECLARE
    invalid_products INTEGER[];
BEGIN
    -- Check if any product IDs don't exist in Products table
    IF NEW.cart IS NOT NULL THEN
        SELECT array_agg(p) INTO invalid_products
        FROM unnest(NEW.cart) p
        LEFT JOIN Products ON Products.product_id = p
        WHERE Products.product_id IS NULL AND p IS NOT NULL;
        
        IF invalid_products IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid product IDs in cart: %', invalid_products;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_customer_cart
BEFORE INSERT OR UPDATE OF cart ON Customers
FOR EACH ROW
EXECUTE FUNCTION validate_customer_cart();

CREATE OR REPLACE FUNCTION cleanup_customer_orders()
RETURNS TRIGGER AS $$
BEGIN
    -- Remove deleted order IDs from all customers' orders arrays
    UPDATE Customers
    SET orders = array_remove(orders, OLD.order_id)
    WHERE OLD.order_id = ANY(orders);
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER remove_deleted_orders
AFTER DELETE ON Orders
FOR EACH ROW
EXECUTE FUNCTION cleanup_customer_orders();

CREATE OR REPLACE FUNCTION cleanup_customer_carts()
RETURNS TRIGGER AS $$
BEGIN
    -- Remove deleted product IDs from all customers' carts
    UPDATE Customers
    SET cart = array_remove(cart, OLD.product_id)
    WHERE OLD.product_id = ANY(cart);
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER remove_deleted_products
AFTER DELETE ON Products
FOR EACH ROW
EXECUTE FUNCTION cleanup_customer_carts();

CREATE OR REPLACE FUNCTION check_payment_before_delivery()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'delivered' AND NOT NEW.payment THEN
        RAISE EXCEPTION 'Cannot mark order as delivered without payment confirmation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_delivery_without_payment
BEFORE UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION check_payment_before_delivery();

CREATE OR REPLACE FUNCTION manage_inventory_on_order_change()
RETURNS TRIGGER AS $$
DECLARE
    i INTEGER;
    product_id_val INTEGER;
    quantity_val INTEGER;
    current_stock INTEGER;
    current_reserved INTEGER;
    product_name TEXT;
BEGIN
    -- Handle order confirmation (reserve inventory)
    IF NEW.status = 'confirmed' AND OLD.status = 'cart' THEN
        FOR i IN 1..array_length(NEW.items, 1) LOOP
            product_id_val := NEW.items[i];
            quantity_val := NEW.quantities[i];
            
            SELECT quantity_in_stock, reserved_quantity, p.name 
            INTO current_stock, current_reserved, product_name
            FROM Inventory i
            JOIN Products p ON i.product_id = p.product_id
            WHERE i.product_id = product_id_val FOR UPDATE;
            
            IF (current_stock - current_reserved) < quantity_val THEN
                RAISE EXCEPTION 
                    'Insufficient available stock for product % (ID: %). Requested: %, Available: %', 
                    product_name, product_id_val, quantity_val, (current_stock - current_reserved);
            END IF;
            
            UPDATE Inventory 
            SET reserved_quantity = reserved_quantity + quantity_val
            WHERE product_id = product_id_val;
        END LOOP;
    
    -- Handle order cancellation (release reserved inventory)
    ELSIF NEW.status = 'cancelled' AND OLD.status = 'confirmed' THEN
        FOR i IN 1..array_length(NEW.items, 1) LOOP
            UPDATE Inventory 
            SET reserved_quantity = reserved_quantity - NEW.quantities[i]
            WHERE product_id = NEW.items[i];
        END LOOP;
    
    -- Handle order shipping (convert reserved to actual deduction)
    ELSIF NEW.status = 'shipped' AND OLD.status = 'confirmed' THEN
        FOR i IN 1..array_length(NEW.items, 1) LOOP
            UPDATE Inventory 
            SET quantity_in_stock = quantity_in_stock - NEW.quantities[i],
                reserved_quantity = reserved_quantity - NEW.quantities[i],
                last_stock_update = CURRENT_TIMESTAMP
            WHERE product_id = NEW.items[i];
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER inventory_management
BEFORE UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION manage_inventory_on_order_change();

CREATE OR REPLACE FUNCTION track_customer_orders()
RETURNS TRIGGER AS $$
BEGIN
    -- Add to customer's orders array when confirmed
    IF NEW.status = 'confirmed' AND OLD.status = 'cart' THEN
        UPDATE Customers
        SET orders = array_append(orders, NEW.order_id)
        WHERE customer_id = NEW.customer_id;
    
    -- Remove from cart if cancelled
    ELSIF NEW.status = 'cancelled' AND OLD.status = 'cart' THEN
        UPDATE Customers
        SET cart = array_remove(cart, NEW.items[1])
        WHERE customer_id = NEW.customer_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER customer_order_tracking
AFTER UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION track_customer_orders();

-- Core performance indexes
CREATE INDEX idx_orders_status ON Orders(status);
CREATE INDEX idx_orders_customer ON Orders(customer_id);
CREATE INDEX idx_products_supplier ON Products(supplier_id);
CREATE INDEX idx_customer_email ON Customers(email);

-- GIN indexes for array columns
CREATE INDEX idx_customer_cart ON Customers USING GIN(cart);
CREATE INDEX idx_customer_orders ON Customers USING GIN(orders);
CREATE INDEX idx_order_items ON Orders USING GIN(items);

-- Partial indexes with corrections
CREATE INDEX idx_active_suppliers ON Supplier(supplier_id) WHERE active = TRUE;
CREATE INDEX idx_available_inventory ON Inventory(product_id) 
    WHERE (quantity_in_stock - reserved_quantity) > 0;
    
-- Updated to reflect current order_status enum values
CREATE INDEX idx_unpaid_orders ON Orders(order_id) 
    WHERE payment = FALSE AND status <> 'cart';

--