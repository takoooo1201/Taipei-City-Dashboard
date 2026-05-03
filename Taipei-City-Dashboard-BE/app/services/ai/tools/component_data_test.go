package tools

import "testing"

func TestExtractSingleSourceTableAllowsSimpleSelect(t *testing.T) {
	tests := []struct {
		name  string
		query string
		want  string
	}{
		{
			name:  "schema qualified table",
			query: "select x_axis, data from public.bike_network_tpe where direction != '' group by direction",
			want:  "public.bike_network_tpe",
		},
		{
			name:  "plain table",
			query: "SELECT * FROM tran_ubike_realtime",
			want:  "tran_ubike_realtime",
		},
		{
			name:  "escaped newlines from seed SQL",
			query: `select * \r\nfrom public.bus_info_tpe\r\nwhere plate_numb like 'E%'`,
			want:  "public.bus_info_tpe",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ExtractSingleSourceTable(tt.query)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestExtractSingleSourceTableRejectsComplexQueries(t *testing.T) {
	tests := []struct {
		name  string
		query string
	}{
		{name: "cte", query: "with d as (select * from public.a) select * from d"},
		{name: "subquery", query: "select x from (select * from public.a) d"},
		{name: "join", query: "select * from public.a join public.b on a.id = b.id"},
		{name: "union", query: "select * from public.a union all select * from public.b"},
		{name: "multiple tables", query: "select * from public.a, public.b"},
		{name: "non select", query: "delete from public.a"},
		{name: "unsafe table", query: "select * from public.a;drop"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got, err := ExtractSingleSourceTable(tt.query); err == nil {
				t.Fatalf("got table %q, want error", got)
			}
		})
	}
}

func TestNormalizeComponentDataLimit(t *testing.T) {
	tests := []struct {
		limit int
		want  int
	}{
		{limit: 0, want: 70},
		{limit: -1, want: 70},
		{limit: 10, want: 10},
		{limit: 100, want: 70},
	}

	for _, tt := range tests {
		if got := normalizeComponentDataLimit(tt.limit); got != tt.want {
			t.Fatalf("limit %d got %d, want %d", tt.limit, got, tt.want)
		}
	}
}
