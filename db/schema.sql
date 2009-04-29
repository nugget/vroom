CREATE TABLE versions (
  version_id integer NOT NULL,
  created timestamp(0) NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  language varchar NOT NULL DEFAULT 'en',
  PRIMARY KEY(version_id)
);

CREATE TABLE vehicles (
  vehicle_id serial NOT NULL,
  name varchar NOT NULL,
  units_odometer varchar NOT NULL DEFAULT 'mi',
  units_economy varchar NOT NULL DEFAULT 'MPG',
  notes text,
  PRIMARY KEY(vehicle_id)
);

CREATE TABLE trips (
  trip_id serial NOT NULL,
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  name varchar NOT NULL,
  start_date date NOT NULL,
  start_odometer numeric(8,1) NOT NULL,
  end_date date,
  end_odometer numeric(8,1),
  note text,
  distance numeric(8,1),
  PRIMARY KEY(trip_id)
);

CREATE TABLE expenses (
  expense_id serial NOT NULL,
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  name varchar NOT NULL,
  service_date date NOT NULL,
  odometer numeric(8,1) NOT NULL,
  cost money NOT NULL,
  note text,
  location varchar,
  type varchar,
  subtype varchar,
  payment varchar,
  categories varchar,
  reminder_interval varchar,
  reminder_distance numeric(8,1),
  flags integer,
  PRIMARY KEY(expense_id)
);

CREATE TABLE fillups (
  fillup_id serial NOT NULL,
  vehicle_id integer NOT NULL REFERENCES vehicles(vehicle_id),
  odometer numeric(8,1) NOT NULL,
  trip_odometer numeric(5,1),
  fillup_date date NOT NULL,
  fill_amount numeric(6,3) NOT NULL,
  fill_units varchar NOT NULL DEFAULT 'Gal',
  unit_price numeric (5,3) NOT NULL,
  total_price money NOT NULL,
  partial_fill boolean NOT NULL DEFAULT FALSE,
  mpg numeric(6,3) NOT NULL,
  note text,
  octane varchar,
  location varchar,
  payment varchar,
  conditions varchar,
  reset boolean NOT NULL DEFAULT FALSE,
  categories varchar,
  flags integer,
  PRIMARY KEY(fillup_id)
);

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
