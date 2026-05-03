package tools

import (
	"TaipeiCityDashboardBE/app/models"
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"gorm.io/gorm/clause"
)

const (
	componentDataMaxRows = 70
	taipeiTimeLayout     = "2006-01-02T15:04:05+08:00"
)

type ComponentDataArgs struct {
	ComponentID int    `json:"component_id"`
	City        string `json:"city"`
	DataKind    string `json:"data_kind"`
	TimeFrom    string `json:"time_from"`
	TimeTo      string `json:"time_to"`
	Limit       int    `json:"limit"`
}

type componentDataResponse struct {
	Component      componentDataMeta `json:"component"`
	DataKind       string            `json:"data_kind"`
	Data           interface{}       `json:"data"`
	Categories     []string          `json:"categories,omitempty"`
	RawSourceTable string            `json:"raw_source_table,omitempty"`
	Limit          int               `json:"limit,omitempty"`
	Warning        string            `json:"warning,omitempty"`
}

type componentDataMeta struct {
	ID    int64  `json:"id"`
	Index string `json:"index"`
	Name  string `json:"name"`
	City  string `json:"city"`
}

// GetComponentData lets the LLM fetch component chart, history, or safe raw rows.
func GetComponentData(ctx context.Context, args string) (string, error) {
	var params ComponentDataArgs
	if err := parseArgs(args, &params); err != nil {
		return "", fmt.Errorf("invalid arguments: %v", err)
	}

	if params.ComponentID <= 0 {
		return "", fmt.Errorf("component_id must be positive")
	}
	if params.City != "taipei" && params.City != "metrotaipei" {
		return "", fmt.Errorf("city must be taipei or metrotaipei")
	}

	timeFrom, timeTo, err := componentDataTimeRange(params.TimeFrom, params.TimeTo)
	if err != nil {
		return "", err
	}

	component, err := models.GetComponentByID(params.ComponentID, params.City)
	if err != nil {
		return "", fmt.Errorf("component not found: %v", err)
	}

	resp := componentDataResponse{
		Component: componentDataMeta{
			ID: component.ID, Index: component.Index, Name: component.Name, City: component.City,
		},
		DataKind: params.DataKind,
	}

	switch params.DataKind {
	case "chart":
		return getComponentChartData(params.ComponentID, params.City, timeFrom, timeTo, resp)
	case "history":
		return getComponentHistoryData(params.ComponentID, params.City, timeFrom, timeTo, resp)
	case "raw":
		return getComponentRawRows(ctx, params.ComponentID, params.City, params.Limit, resp)
	default:
		return "", fmt.Errorf("data_kind must be chart, history, or raw")
	}
}

func getComponentChartData(componentID int, city string, timeFrom string, timeTo string, resp componentDataResponse) (string, error) {
	queryType, queryString, err := models.GetComponentChartDataQuery(componentID, city)
	if err != nil {
		return "", err
	}
	if queryType == "" || queryString == "" {
		resp.Warning = "No chart data is configured for this component."
		return marshalToolResponse(resp)
	}

	switch queryType {
	case "two_d":
		data, err := models.GetTwoDimensionalData(&queryString, timeFrom, timeTo)
		resp.Data = data
		return marshalToolResponseWithErr(resp, err)
	case "three_d", "percent":
		data, categories, err := models.GetThreeDimensionalData(&queryString, timeFrom, timeTo)
		resp.Data = data
		resp.Categories = categories
		return marshalToolResponseWithErr(resp, err)
	case "time":
		data, err := models.GetTimeSeriesData(&queryString, timeFrom, timeTo)
		resp.Data = data
		return marshalToolResponseWithErr(resp, err)
	case "map_legend":
		data, err := models.GetMapLegendData(&queryString, timeFrom, timeTo)
		resp.Data = data
		return marshalToolResponseWithErr(resp, err)
	default:
		resp.Warning = fmt.Sprintf("Unsupported chart query_type: %s.", queryType)
		return marshalToolResponse(resp)
	}
}

func getComponentHistoryData(componentID int, city string, timeFrom string, timeTo string, resp componentDataResponse) (string, error) {
	queryHistory, err := models.GetComponentHistoryDataQuery(componentID, city, timeFrom, timeTo)
	if err != nil {
		return "", err
	}
	if queryHistory == "" {
		resp.Warning = "No history data is configured for this component."
		return marshalToolResponse(resp)
	}

	data, err := models.GetTimeSeriesData(&queryHistory, timeFrom, timeTo)
	resp.Data = data
	return marshalToolResponseWithErr(resp, err)
}

func getComponentRawRows(ctx context.Context, componentID int, city string, limit int, resp componentDataResponse) (string, error) {
	_, queryString, err := models.GetComponentChartDataQuery(componentID, city)
	if err != nil {
		return "", err
	}

	tableName, err := ExtractSingleSourceTable(queryString)
	if err != nil {
		resp.Warning = "Unable to safely get raw rows from this component. Please use chart or history data instead."
		resp.Limit = normalizeComponentDataLimit(limit)
		return marshalToolResponse(resp)
	}

	rows, usedLimit, err := queryRawRows(ctx, tableName, limit)
	if err != nil {
		return "", err
	}

	resp.RawSourceTable = tableName
	resp.Limit = usedLimit
	resp.Data = rows
	return marshalToolResponse(resp)
}

func queryRawRows(ctx context.Context, tableName string, limit int) ([]map[string]interface{}, int, error) {
	usedLimit := normalizeComponentDataLimit(limit)
	query := models.DBDashboard.WithContext(ctx).Table(tableName).Limit(usedLimit)
	if orderColumn := preferredRawOrderColumn(tableName); orderColumn != "" {
		query = query.Order(clause.OrderByColumn{Column: clause.Column{Name: orderColumn}, Desc: true})
	}

	var rows []map[string]interface{}
	if err := query.Find(&rows).Error; err != nil {
		return nil, usedLimit, err
	}
	normalizeRawRows(rows)
	return rows, usedLimit, nil
}

func preferredRawOrderColumn(tableName string) string {
	for _, column := range []string{"data_time", "updated_at", "created_at", "id"} {
		if models.DBDashboard.Migrator().HasColumn(tableName, column) {
			return column
		}
	}
	return ""
}

func normalizeComponentDataLimit(limit int) int {
	if limit <= 0 {
		return componentDataMaxRows
	}
	if limit > componentDataMaxRows {
		return componentDataMaxRows
	}
	return limit
}

func componentDataTimeRange(timeFrom string, timeTo string) (string, string, error) {
	if timeFrom == "" {
		timeFrom = time.Date(1990, 1, 1, 0, 0, 0, 0, time.FixedZone("UTC+8", 8*60*60)).Format(taipeiTimeLayout)
	} else if _, err := time.Parse(taipeiTimeLayout, timeFrom); err != nil {
		return "", "", fmt.Errorf("time_from must use format %s", taipeiTimeLayout)
	}

	if timeTo == "" {
		timeTo = time.Now().Format(taipeiTimeLayout)
	} else if _, err := time.Parse(taipeiTimeLayout, timeTo); err != nil {
		return "", "", fmt.Errorf("time_to must use format %s", taipeiTimeLayout)
	}

	return timeFrom, timeTo, nil
}

func marshalToolResponseWithErr(resp componentDataResponse, err error) (string, error) {
	if err != nil {
		return "", err
	}
	return marshalToolResponse(resp)
}

func marshalToolResponse(resp componentDataResponse) (string, error) {
	b, err := json.Marshal(resp)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

var safeTableIdentifier = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?$`)

// ExtractSingleSourceTable returns a single table from a simple SELECT query.
// It intentionally rejects joins, CTEs, subqueries, unions, and multi-table queries.
func ExtractSingleSourceTable(query string) (string, error) {
	cleaned := normalizeSQLForRawParsing(query)
	cleaned = strings.TrimSpace(strings.TrimSuffix(cleaned, ";"))
	if strings.Contains(cleaned, ";") {
		return "", fmt.Errorf("multiple statements are not supported")
	}

	lower := strings.ToLower(cleaned)
	if cleaned == "" {
		return "", fmt.Errorf("empty query")
	}
	if !strings.HasPrefix(lower, "select ") {
		return "", fmt.Errorf("only select queries are supported")
	}
	if strings.HasPrefix(lower, "with ") || strings.Contains(lower, " union ") || strings.Contains(lower, " join ") || strings.Contains(lower, " from (") {
		return "", fmt.Errorf("complex queries are not supported")
	}

	fromIdx := strings.Index(lower, " from ")
	if fromIdx < 0 || strings.Count(lower, " from ") != 1 {
		return "", fmt.Errorf("query must contain exactly one from clause")
	}

	afterFrom := strings.TrimSpace(cleaned[fromIdx+len(" from "):])
	if afterFrom == "" || strings.HasPrefix(afterFrom, "(") {
		return "", fmt.Errorf("missing source table")
	}

	tableExpr := firstSQLToken(afterFrom)
	tableExpr = strings.Trim(tableExpr, `"`)
	if tableExpr == "" || !safeTableIdentifier.MatchString(tableExpr) {
		return "", fmt.Errorf("unsafe source table")
	}

	remaining := strings.TrimSpace(afterFrom[len(firstSQLToken(afterFrom)):])
	if containsDisallowedTableSeparator(remaining) {
		return "", fmt.Errorf("multiple source tables are not supported")
	}

	return tableExpr, nil
}

func normalizeSQLForRawParsing(query string) string {
	query = stripSQLLineComments(query)
	query = strings.ReplaceAll(query, `\r`, " ")
	query = strings.ReplaceAll(query, `\n`, " ")
	query = strings.ReplaceAll(query, "\r", " ")
	query = strings.ReplaceAll(query, "\n", " ")
	return strings.Join(strings.Fields(strings.TrimSpace(query)), " ")
}

func stripSQLLineComments(query string) string {
	lines := strings.Split(query, "\n")
	for i, line := range lines {
		if idx := strings.Index(line, "--"); idx >= 0 {
			lines[i] = line[:idx]
		}
	}
	return strings.Join(lines, "\n")
}

func firstSQLToken(input string) string {
	for i, r := range input {
		if r == ' ' || r == '\t' || r == '\r' || r == '\n' || r == ';' {
			return input[:i]
		}
	}
	return input
}

func containsDisallowedTableSeparator(remaining string) bool {
	if remaining == "" {
		return false
	}

	lower := strings.ToLower(remaining)
	for _, keyword := range []string{" where ", " group ", " order ", " limit ", " offset ", " having ", " fetch ", " for "} {
		if strings.HasPrefix(lower, strings.TrimLeft(keyword, " ")) {
			return false
		}
	}

	return strings.Contains(remaining, ",") || strings.Contains(lower, " join ") || strings.HasPrefix(lower, ",") || strings.HasPrefix(lower, "join ")
}

func normalizeRawRows(rows []map[string]interface{}) {
	for _, row := range rows {
		for key, value := range row {
			switch typed := value.(type) {
			case []byte:
				row[key] = string(typed)
			case time.Time:
				row[key] = typed.Format(time.RFC3339)
			}
		}
	}
}
