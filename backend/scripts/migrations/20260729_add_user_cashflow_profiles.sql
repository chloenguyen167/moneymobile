CREATE TABLE IF NOT EXISTS user_cashflow_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id),
    starting_balance DOUBLE PRECISION NOT NULL,
    monthly_income DOUBLE PRECISION NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'VND',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_user_cashflow_profiles_user_id
ON user_cashflow_profiles (user_id);
