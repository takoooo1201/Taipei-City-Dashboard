-- Register the school_locations dashboard component.
--
-- Usage example from this repository root:
--   docker cp C:\Users\tako\taipei_city_dashboard\final_school_coords.csv postgres-data:/tmp/final_school_coords.csv
--   docker cp data/register_school_locations_component.sql postgres-data:/tmp/register_school_locations_component.sql
--   docker exec -e PGPASSWORD=tako1234 postgres-data psql -U postgres -d dashboard -f /tmp/register_school_locations_component.sql
--
-- The script imports the CSV as UTF-8, rebuilds the dashboard.school_locations
-- table, exports the GeoJSON files to /tmp inside postgres-data, and registers
-- the component/dashboard records in dashboardmanager.
--
-- After running, copy the generated GeoJSON files into the frontend public folder:
--   docker cp postgres-data:/tmp/school_locations.geojson Taipei-City-Dashboard-FE/public/mapData/school_locations.geojson
--   docker cp postgres-data:/tmp/school_locations_rings.geojson Taipei-City-Dashboard-FE/public/mapData/school_locations_rings.geojson

\set ON_ERROR_STOP on
\encoding UTF8

\connect dashboard

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS public.school_locations (
	ogc_fid serial PRIMARY KEY,
	level text,
	level_key text,
	county text,
	district text,
	school_code text,
	school_name text,
	address text,
	phone text,
	lon double precision,
	lat double precision,
	wkb_geometry geometry(Point, 4326),
	_ctime timestamp with time zone DEFAULT NOW(),
	_mtime timestamp with time zone DEFAULT NOW()
);

CREATE TEMP TABLE school_locations_import (
	"學校級別" text,
	"縣市名稱" text,
	"鄉鎮市區" text,
	"學校代碼" text,
	"學校名稱" text,
	"地址" text,
	"電話" text,
	"經度" text,
	"緯度" text
);

\copy school_locations_import ("學校級別", "縣市名稱", "鄉鎮市區", "學校代碼", "學校名稱", "地址", "電話", "經度", "緯度") FROM '/tmp/final_school_coords.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

TRUNCATE TABLE public.school_locations RESTART IDENTITY;

INSERT INTO public.school_locations (
	level,
	level_key,
	county,
	district,
	school_code,
	school_name,
	address,
	phone,
	lon,
	lat,
	wkb_geometry,
	_ctime,
	_mtime
)
SELECT
	"學校級別",
	CASE "學校級別"
		WHEN '高級中等學校' THEN 'senior_high'
		WHEN '國民中學' THEN 'junior_high'
		WHEN '國民小學' THEN 'elementary'
		WHEN '大專校院' THEN 'university'
		WHEN '特殊教育學校' THEN 'special_ed'
		WHEN '附設國民中學' THEN 'attached_junior_high'
		WHEN '附設國民小學' THEN 'attached_elementary'
		WHEN '宗教研修學院' THEN 'religious_college'
		WHEN '空大及大專校院附設進修學校' THEN 'continuing_ed'
		ELSE 'other'
	END AS level_key,
	"縣市名稱",
	"鄉鎮市區",
	"學校代碼",
	"學校名稱",
	"地址",
	"電話",
	NULLIF("經度", '')::double precision,
	NULLIF("緯度", '')::double precision,
	ST_SetSRID(
		ST_MakePoint(NULLIF("經度", '')::double precision, NULLIF("緯度", '')::double precision),
		4326
	),
	NOW(),
	NOW()
FROM school_locations_import
WHERE NULLIF("經度", '') IS NOT NULL
	AND NULLIF("緯度", '') IS NOT NULL;

CREATE INDEX IF NOT EXISTS school_locations_wkb_geometry_idx
	ON public.school_locations
	USING gist (wkb_geometry);

CREATE INDEX IF NOT EXISTS school_locations_level_key_idx
	ON public.school_locations (level_key);

COMMIT;

COPY (
	WITH features AS (
		SELECT jsonb_build_object(
			'type', 'Feature',
			'geometry', ST_AsGeoJSON(wkb_geometry)::jsonb,
			'properties', jsonb_build_object(
				'level', level,
				'level_key', level_key,
				'county', county,
				'district', district,
				'school_code', school_code,
				'school_name', school_name,
				'address', address,
				'phone', phone,
				'lon', lon,
				'lat', lat
			)
		) AS feature
		FROM public.school_locations
		ORDER BY ogc_fid
	)
	SELECT jsonb_build_object(
		'type', 'FeatureCollection',
		'features', jsonb_agg(feature)
	)::text
	FROM features
) TO '/tmp/school_locations.geojson';

COPY (
	WITH ring_features AS (
		SELECT jsonb_build_object(
			'type', 'Feature',
			'geometry', ST_AsGeoJSON(
				ST_Buffer(wkb_geometry::geography, 300, 'quad_segs=24')::geometry
			)::jsonb,
			'properties', jsonb_build_object(
				'level', level,
				'level_key', level_key,
				'county', county,
				'district', district,
				'school_code', school_code,
				'school_name', school_name,
				'address', address,
				'phone', phone,
				'ring_label', '300 公尺',
				'radius_m', 300
			)
		) AS feature
		FROM public.school_locations
		ORDER BY ogc_fid
	)
	SELECT jsonb_build_object(
		'type', 'FeatureCollection',
		'features', jsonb_agg(feature)
	)::text
	FROM ring_features
) TO '/tmp/school_locations_rings.geojson';

\connect postgresql://postgres@postgres-manager:5432/dashboardmanager

BEGIN;

INSERT INTO public.components (id, index, name)
VALUES (902, 'school_locations', '雙北學校分布')
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	name = EXCLUDED.name;

INSERT INTO public.component_charts (index, color, types, unit)
VALUES (
	'school_locations',
	ARRAY[
		'#4FC3F7',
		'#FFA726',
		'#66BB6A',
		'#2E7D32',
		'#EF5350',
		'#0288D1',
		'#FBC02D',
		'#8D6E63',
		'#AB47BC'
	],
	ARRAY['DonutChart', 'ColumnChart', 'BarChart'],
	'所'
)
ON CONFLICT (index) DO UPDATE SET
	color = EXCLUDED.color,
	types = EXCLUDED.types,
	unit = EXCLUDED.unit;

INSERT INTO public.component_maps (
	id,
	index,
	title,
	type,
	source,
	size,
	icon,
	paint,
	property
)
VALUES (
	902,
	'school_locations_rings',
	'學校300m範圍',
	'fill',
	'geojson',
	NULL,
	NULL,
	$paint$
	{
		"fill-color": [
			"match",
			["get", "level_key"],
			"senior_high", "#4FC3F7",
			"junior_high", "#FFA726",
			"elementary", "#66BB6A",
			"university", "#AB47BC",
			"special_ed", "#EF5350",
			"attached_junior_high", "#0288D1",
			"attached_elementary", "#2E7D32",
			"religious_college", "#8D6E63",
			"continuing_ed", "#FBC02D",
			"#9E9E9E"
		],
		"fill-opacity": [
			"interpolate",
			["linear"],
			["zoom"],
			9, 0.16,
			12, 0.24,
			16, 0.36
		],
		"fill-outline-color": "rgba(255,255,255,0)"
	}
	$paint$::json,
	$property$
	[
		{"key":"school_name","name":"學校名稱"},
		{"key":"level","name":"學校級別"},
		{"key":"county","name":"縣市"},
		{"key":"district","name":"行政區"},
		{"key":"school_code","name":"學校代碼"},
		{"key":"ring_label","name":"半徑"},
		{"key":"address","name":"地址"},
		{"key":"phone","name":"電話"}
	]
	$property$::json
)
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	title = EXCLUDED.title,
	type = EXCLUDED.type,
	source = EXCLUDED.source,
	size = EXCLUDED.size,
	icon = EXCLUDED.icon,
	paint = EXCLUDED.paint,
	property = EXCLUDED.property;

INSERT INTO public.component_maps (
	id,
	index,
	title,
	type,
	source,
	size,
	icon,
	paint,
	property
)
VALUES (
	903,
	'school_locations_rings',
	'300m範圍邊界',
	'line',
	'geojson',
	NULL,
	NULL,
	$paint$
	{
		"line-color": [
			"match",
			["get", "level_key"],
			"senior_high", "#4FC3F7",
			"junior_high", "#FFA726",
			"elementary", "#66BB6A",
			"university", "#AB47BC",
			"special_ed", "#EF5350",
			"attached_junior_high", "#0288D1",
			"attached_elementary", "#2E7D32",
			"religious_college", "#8D6E63",
			"continuing_ed", "#FBC02D",
			"#9E9E9E"
		],
		"line-opacity": [
			"interpolate",
			["linear"],
			["zoom"],
			9, 0.35,
			12, 0.55,
			16, 0.85
		],
		"line-width": [
			"interpolate",
			["linear"],
			["zoom"],
			9, 0.35,
			12, 0.75,
			16, 1.4
		]
	}
	$paint$::json,
	$property$
	[
		{"key":"school_name","name":"學校名稱"},
		{"key":"level","name":"學校級別"},
		{"key":"county","name":"縣市"},
		{"key":"district","name":"行政區"},
		{"key":"school_code","name":"學校代碼"},
		{"key":"ring_label","name":"半徑"},
		{"key":"address","name":"地址"},
		{"key":"phone","name":"電話"}
	]
	$property$::json
)
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	title = EXCLUDED.title,
	type = EXCLUDED.type,
	source = EXCLUDED.source,
	size = EXCLUDED.size,
	icon = EXCLUDED.icon,
	paint = EXCLUDED.paint,
	property = EXCLUDED.property;

INSERT INTO public.component_maps (
	id,
	index,
	title,
	type,
	source,
	size,
	icon,
	paint,
	property
)
VALUES (
	904,
	'school_locations',
	'學校中心',
	'circle',
	'geojson',
	'small',
	NULL,
	$paint$
	{
		"circle-color": "#ffffff",
		"circle-stroke-color": [
			"match",
			["get", "level_key"],
			"senior_high", "#4FC3F7",
			"junior_high", "#FFA726",
			"elementary", "#66BB6A",
			"university", "#AB47BC",
			"special_ed", "#EF5350",
			"attached_junior_high", "#0288D1",
			"attached_elementary", "#2E7D32",
			"religious_college", "#8D6E63",
			"continuing_ed", "#FBC02D",
			"#9E9E9E"
		],
		"circle-stroke-width": 1.2,
		"circle-opacity": 0.95
	}
	$paint$::json,
	$property$
	[
		{"key":"school_name","name":"學校名稱"},
		{"key":"level","name":"學校級別"},
		{"key":"county","name":"縣市"},
		{"key":"district","name":"行政區"},
		{"key":"school_code","name":"學校代碼"},
		{"key":"address","name":"地址"},
		{"key":"phone","name":"電話"}
	]
	$property$::json
)
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	title = EXCLUDED.title,
	type = EXCLUDED.type,
	source = EXCLUDED.source,
	size = EXCLUDED.size,
	icon = EXCLUDED.icon,
	paint = EXCLUDED.paint,
	property = EXCLUDED.property;

DELETE FROM public.query_charts
WHERE index = 'school_locations'
	AND city IN ('taipei', 'metrotaipei');

INSERT INTO public.query_charts (
	index,
	history_config,
	map_config_ids,
	map_filter,
	time_from,
	time_to,
	update_freq,
	update_freq_unit,
	source,
	short_desc,
	long_desc,
	use_case,
	links,
	contributors,
	created_at,
	updated_at,
	query_type,
	query_chart,
	query_history,
	city
)
SELECT
	'school_locations',
	NULL,
	ARRAY[902, 903, 904],
	'{"mode":"byParam","byParam":{"xParam":"level"}}'::json,
	'static',
	NULL,
	NULL,
	NULL,
	'CSV',
	'雙北學校位置點位',
	'以每所學校為中心產生 300 公尺範圍，呈現雙北學校周邊分布。',
	'可用於觀察各校周邊 300 公尺服務半徑與雙北學校空間密度；此範圍為視覺化參考，非官方學區。',
	ARRAY[]::text[],
	ARRAY[]::text[],
	NOW(),
	NOW(),
	'two_d',
	$chart_sql$
	SELECT level AS x_axis, COUNT(*)::float AS data
	FROM public.school_locations
	GROUP BY level, level_key
	ORDER BY CASE level_key
		WHEN 'elementary' THEN 1
		WHEN 'junior_high' THEN 2
		WHEN 'senior_high' THEN 3
		WHEN 'university' THEN 4
		WHEN 'attached_elementary' THEN 5
		WHEN 'attached_junior_high' THEN 6
		WHEN 'special_ed' THEN 7
		WHEN 'religious_college' THEN 8
		WHEN 'continuing_ed' THEN 9
		ELSE 99
	END
	$chart_sql$,
	NULL,
	city
FROM (VALUES ('taipei'), ('metrotaipei')) AS cities(city);

INSERT INTO public.dashboards (
	id,
	index,
	name,
	components,
	icon,
	updated_at,
	created_at
)
VALUES (
	365,
	'schools_taipei',
	'學校分布',
	ARRAY[902],
	'school',
	NOW(),
	NOW()
)
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	name = EXCLUDED.name,
	components = EXCLUDED.components,
	icon = EXCLUDED.icon,
	updated_at = NOW();

INSERT INTO public.dashboard_groups (dashboard_id, group_id)
VALUES
	(365, 2),
	(365, 3)
ON CONFLICT DO NOTHING;

SELECT setval('public.components_id_seq', GREATEST((SELECT MAX(id) FROM public.components), 1), true);
SELECT setval('public.component_maps_id_seq', GREATEST((SELECT MAX(id) FROM public.component_maps), 1), true);
SELECT setval('public.dashboards_id_seq', GREATEST((SELECT MAX(id) FROM public.dashboards), 1), true);

COMMIT;
