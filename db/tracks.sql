CREATE TABLE tracks (
  track_id serial NOT NULL,
  created timestamp(0) NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
  name varchar NOT NULL,
  abbr varchar NOT NULL,
  regexp varchar NOT NULL,
  notes text,
  map_large_url varchar,
  map_small_url varchar,
  PRIMARY KEY(track_id)
);

INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Harris Hill Road', 'H2R', '(H2R|Harris Hill)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Texas World Speedway', 'TWS', '(Texas World|TWS)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Motorsport Ranch Cresson', 'Cresson', '(Cresson|MSRC)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Eagle''s Canyon Raceway', 'ECR', '(ECR|Eagle)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Motorsport Ranch Houston', 'MSRH', '(Houston|MSRH)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Driveway Austin', 'Driveway', '(Driveway)');
INSERT INTO TRACKS (name,abbr,regexp) VALUES ('Grandsport Speedway', 'GS', '(GS|Grandsport)');

