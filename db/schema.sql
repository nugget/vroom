CREATE ROLE wwwuser WITH LOGIN ENCRYPTED PASSWORD 'password';

CREATE TABLE versions (
  version_id integer NOT NULL,
  created timestamp(0) NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  language varchar NOT NULL DEFAULT 'en',
  PRIMARY KEY(version_id)
);
GRANT SELECT,INSERT ON versions TO wwwuser;

CREATE TABLE vehicles (
  vehicle_id serial NOT NULL,
  added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  name varchar NOT NULL,
  units_odometer varchar NOT NULL DEFAULT 'mi',
  units_economy varchar NOT NULL DEFAULT 'MPG',
  notes text,
  tag varchar,
  tank_capacity numeric(5,2),
  tank_units varchar NOT NULL DEFAULT 'gal',
  home_currency varchar NOT NULL DEFAULT 'USD',
  uuid varchar,
  dropbox_url varchar,
  PRIMARY KEY(vehicle_id)
);
GRANT SELECT,INSERT ON vehicles TO wwwuser;
GRANT ALL ON vehicles_vehicle_id_seq TO wwwuser;

CREATE TABLE trips (
  trip_id serial NOT NULL,
  added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  name varchar NOT NULL,
  start_date date NOT NULL,
  start_odometer numeric(8,1) NOT NULL,
  end_date date,
  end_odometer numeric(8,1),
  note text,
  distance numeric(8,1),
  heat_cycles integer,
  flags integer,
  categories varchar,
  uuid varchar,
  PRIMARY KEY(trip_id)
);
GRANT SELECT,INSERT,UPDATE ON trips TO wwwuser;
GRANT ALL ON trips_trip_id_seq TO wwwuser;
CREATE TRIGGER onupdate BEFORE UPDATE ON trips FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();

CREATE TABLE expenses (
  expense_id serial NOT NULL,
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  name varchar NOT NULL,
  service_date date NOT NULL,
  odometer numeric(8,1) NOT NULL,
  cost numeric (8,2) NOT NULL,
  note text,
  location varchar,
  type varchar,
  subtype varchar,
  payment varchar,
  categories varchar,
  reminder_interval varchar,
  reminder_distance numeric(8,1),
  flags integer NOT NULL DEFAULT 0,
  currency_code varchar,
  currency_rate numeric(10,6) NOT NULL DEFAULT 1,
  PRIMARY KEY(expense_id)
);
GRANT SELECT,INSERT,UPDATE ON expenses TO wwwuser;
GRANT ALL ON expenses_expense_id_seq TO wwwuser;

CREATE TABLE fillups (
  fillup_id serial NOT NULL,
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  odometer numeric(8,1) NOT NULL,
  trip_odometer numeric(5,1),
  fillup_date date NOT NULL,
  fill_amount numeric(6,3) NOT NULL,
  fill_units varchar NOT NULL DEFAULT 'Gal',
  unit_price numeric (5,3) NOT NULL,
  total_price numeric (5,2) NOT NULL,
  partial_fill boolean NOT NULL DEFAULT FALSE,
  mpg numeric(6,3) NOT NULL,
  note text,
  octane varchar,
  location varchar,
  payment varchar,
  conditions varchar,
  reset boolean NOT NULL DEFAULT FALSE,
  categories varchar,
  flags integer NOT NULL DEFAULT 0,
  currency_code varchar,
  currency_rate numeric(10,6) NOT NULL DEFAULT 1,
  PRIMARY KEY(fillup_id)
);
GRANT SELECT,INSERT,UPDATE ON fillups TO wwwuser;
GRANT ALL ON fillups_fillup_id_seq TO wwwuser;

CREATE OR REPLACE FUNCTION fillup_calcs() RETURNS trigger AS $$
  BEGIN
    IF NEW.fill_amount IS NOT NULL THEN
      IF NEW.unit_price IS NOT NULL THEN
        NEW.total_price := (NEW.fill_amount * NEW.unit_price);
      ELSE
        IF NEW.total_price IS NOT NULL THEN
          NEW.unit_price := (NEW.total_price / NEW.fill_amount);
	END IF;
      END IF;
    ELSE
      IF NEW.unit_price IS NOT NULL AND NEW.total_price IS NOT NULl THEN
        NEW.fill_amount := (NEW.total_price / NEW.unit_price);
      END IF;
    END IF;

    IF NEW.trip_odometer IS NULL THEN
      NEW.trip_odometer := NEW.odometer - (SELECT max(odometer) FROM fillups WHERE vehicle_id = NEW.vehicle_id AND odometer < NEW.odometer);
    END IF;

    IF NEW.mpg IS NULL THEN
      NEW.mpg := (NEW.trip_odometer / NEW.fill_amount);
    END IF;

    RETURN NEW;

  END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER fillup_extrapolate BEFORE INSERT ON fillups FOR EACH ROW EXECUTE PROCEDURE fillup_calcs();
