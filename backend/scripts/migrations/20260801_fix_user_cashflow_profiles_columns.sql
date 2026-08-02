ALTER TABLE user_cashflow_profiles
ADD COLUMN IF NOT EXISTS monthly_income DOUBLE PRECISION NULL;

ALTER TABLE user_cashflow_profiles
ADD COLUMN IF NOT EXISTS currency VARCHAR(10) NOT NULL DEFAULT 'VND';

ALTER TABLE user_cashflow_profiles
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS ix_user_cashflow_profiles_user_id
ON user_cashflow_profiles (user_id);
