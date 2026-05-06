BEGIN;

INSERT INTO public.components (id, index, name)
VALUES (300, 'food_vendor_rating', '檢核評級業者')
ON CONFLICT (id) DO UPDATE SET
	index = EXCLUDED.index,
	name = EXCLUDED.name;

INSERT INTO public.component_charts (index, color, types, unit)
VALUES ('food_vendor_rating', ARRAY['#35B779', '#F8CF58'], ARRAY['BarChart'], '家')
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
	300,
	'food_vendor_rating',
	'檢核評級業者',
	'circle',
	'geojson',
	'big',
	NULL,
	'{
		"circle-color": ["match", ["get", "rating"], "優", "#35B779", "良", "#F8CF58", "#9CA3AF"],
		"circle-stroke-color": "#ffffff",
		"circle-stroke-width": ["interpolate", ["linear"], ["zoom"], 10, 0.4, 15, 1, 20, 1.5]
	}'::json,
	'[
		{"key": "name", "name": "店名"},
		{"key": "rating", "name": "評核等級"},
		{"key": "address", "name": "地址"},
		{"key": "phone", "name": "電話"},
		{"key": "registration_no", "name": "食品業者登錄字號"}
	]'::json
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
	301,
	'food_vendor_rating_taipei',
	'檢核評級業者',
	'circle',
	'geojson',
	'big',
	NULL,
	'{
		"circle-color": ["match", ["get", "rating"], "優", "#35B779", "良", "#F8CF58", "#9CA3AF"],
		"circle-stroke-color": "#ffffff",
		"circle-stroke-width": ["interpolate", ["linear"], ["zoom"], 10, 0.4, 15, 1, 20, 1.5]
	}'::json,
	'[
		{"key": "name", "name": "店名"},
		{"key": "rating", "name": "評核等級"},
		{"key": "address", "name": "地址"},
		{"key": "phone", "name": "電話"},
		{"key": "registration_no", "name": "食品業者登錄字號"}
	]'::json
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
WHERE index IN ('food_vendor_rating', 'food_vendor_rating_board')
	AND city IN ('metrotaipei', 'taipei');

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
VALUES (
	'food_vendor_rating',
	NULL,
	ARRAY[300],
	NULL,
	'static',
	NULL,
	NULL,
	NULL,
	'CSV',
	'顯示臺北市與新北市檢核評級業者點位。',
	'此組件統計 CSV 內臺北市與新北市檢核評級業者的評核等級數量，分為優與良；地圖圖層仍以點位標示業者位置。',
	'可用於快速比較雙北檢核評級業者中優與良的家數，並搭配地圖查看空間分布。',
	ARRAY[]::text[],
	ARRAY[]::text[],
	NOW(),
	NOW(),
	'two_d',
	$chart_sql$
		SELECT '優'::text AS x_axis, 2330::float AS data
		UNION ALL
		SELECT '良'::text AS x_axis, 85::float AS data
	$chart_sql$,
	NULL,
	'metrotaipei'
);

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
VALUES (
	'food_vendor_rating',
	NULL,
	ARRAY[301],
	NULL,
	'static',
	NULL,
	NULL,
	NULL,
	'CSV',
	'顯示臺北市檢核評級業者點位。',
	'此組件統計 CSV 內臺北市檢核評級業者的評核等級數量，分為優與良；地圖圖層仍以點位標示業者位置。',
	'可用於快速比較臺北市檢核評級業者中優與良的家數，並搭配地圖查看空間分布。',
	ARRAY[]::text[],
	ARRAY[]::text[],
	NOW(),
	NOW(),
	'two_d',
	$chart_sql$
		SELECT '優'::text AS x_axis, 1609::float AS data
		UNION ALL
		SELECT '良'::text AS x_axis, 77::float AS data
	$chart_sql$,
	NULL,
	'taipei'
);

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
	400,
	'food_vendor_rating',
	'檢核評級業者',
	ARRAY[300],
	'restaurant',
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
VALUES (400, 3)
ON CONFLICT DO NOTHING;

INSERT INTO public.dashboard_groups (dashboard_id, group_id)
VALUES (400, 2)
ON CONFLICT DO NOTHING;

UPDATE public.dashboards
SET
	components = CASE
		WHEN components @> ARRAY[300]::integer[] THEN components
		ELSE components || ARRAY[300]::integer[]
	END,
	updated_at = NOW()
WHERE index = 'map-layers-metrotaipei';

UPDATE public.dashboards
SET
	components = CASE
		WHEN components @> ARRAY[300]::integer[] THEN components
		ELSE components || ARRAY[300]::integer[]
	END,
	updated_at = NOW()
WHERE index = 'map-layers-taipei';

DELETE FROM public.component_charts
WHERE index = 'food_vendor_rating_board';

DELETE FROM public.components
WHERE id = 302
	AND index = 'food_vendor_rating_board';

SELECT setval('public.components_id_seq', GREATEST((SELECT MAX(id) FROM public.components), 1), true);
SELECT setval('public.component_maps_id_seq', GREATEST((SELECT MAX(id) FROM public.component_maps), 1), true);
SELECT setval('public.dashboards_id_seq', GREATEST((SELECT MAX(id) FROM public.dashboards), 1), true);

COMMIT;
