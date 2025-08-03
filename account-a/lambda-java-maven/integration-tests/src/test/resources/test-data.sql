-- Test data for integration tests
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    order_number VARCHAR(50) NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    order_date DATE DEFAULT CURRENT_DATE,
    status VARCHAR(20) DEFAULT 'pending'
);

-- Insert test data
INSERT INTO users (username, email, status) VALUES
    ('john_doe', 'john@example.com', 'active'),
    ('jane_smith', 'jane@example.com', 'active'),
    ('mike_wilson', 'mike@example.com', 'inactive'),
    ('sarah_jones', 'sarah@example.com', 'active');

INSERT INTO orders (user_id, order_number, total_amount, status) VALUES
    (1, 'ORD-001', 99.99, 'completed'),
    (1, 'ORD-002', 149.99, 'pending'),
    (2, 'ORD-003', 79.99, 'completed'),
    (4, 'ORD-004', 199.99, 'processing');
