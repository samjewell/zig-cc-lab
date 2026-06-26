// Minimal standalone proof that the zig-cross-compiled, static-musl DuckDB engine
// actually runs queries on Alpine — not just that the plugin binary loads.
package main

import (
	"database/sql"
	"database/sql/driver"
	"fmt"
	"os"
	"runtime"

	duckdb "github.com/duckdb/duckdb-go/v2"
)

func main() {
	connector, err := duckdb.NewConnector("", func(driver.ExecerContext) error { return nil })
	if err != nil {
		fmt.Fprintln(os.Stderr, "NewConnector:", err)
		os.Exit(1)
	}
	db := sql.OpenDB(connector)
	defer db.Close()

	var answer int
	if err := db.QueryRow("SELECT 21 * 2").Scan(&answer); err != nil {
		fmt.Fprintln(os.Stderr, "query:", err)
		os.Exit(1)
	}
	var version string
	_ = db.QueryRow("SELECT version()").Scan(&version)

	fmt.Printf("DuckDB on %s/%s (musl, static): SELECT 21*2 = %d ; version = %s\n",
		runtime.GOOS, runtime.GOARCH, answer, version)
}
