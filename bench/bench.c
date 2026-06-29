// DuckDB -O micro-benchmark harness (C API).
// Generates synthetic data, runs a few compute-heavy queries, prints median/min/max ms.
// Built once and linked against each libduckdb variant (the work happens inside the lib,
// so this harness's own -O level is irrelevant).
//
// Usage: ./bench <rows> <iters> <threads> <label>
#include "duckdb.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static int cmp_d(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

static void run_sql(duckdb_connection con, const char *what, const char *sql) {
    duckdb_result res;
    if (duckdb_query(con, sql, &res) == DuckDBError) {
        fprintf(stderr, "FAILED (%s): %s\n", what, duckdb_result_error(&res));
        duckdb_destroy_result(&res);
        exit(1);
    }
    duckdb_destroy_result(&res);
}

// Run `sql` `iters` times; print median/min/max ms.
static void timed(duckdb_connection con, const char *name, const char *sql, int iters) {
    double *t = (double *)malloc(sizeof(double) * iters);
    for (int i = 0; i < iters; i++) {
        double a = now_ms();
        run_sql(con, name, sql);
        t[i] = now_ms() - a;
    }
    qsort(t, iters, sizeof(double), cmp_d);
    printf("%-12s median=%9.1f ms   min=%9.1f   max=%9.1f   (n=%d)\n",
           name, t[iters / 2], t[0], t[iters - 1], iters);
    fflush(stdout);
    free(t);
}

int main(int argc, char **argv) {
    long rows   = argc > 1 ? atol(argv[1]) : 50000000L;
    int  iters  = argc > 2 ? atoi(argv[2]) : 5;
    int  threads= argc > 3 ? atoi(argv[3]) : 4;
    const char *label = argc > 4 ? argv[4] : "build";

    duckdb_database db;
    duckdb_connection con;
    if (duckdb_open(NULL, &db) == DuckDBError) { fprintf(stderr, "open failed\n"); return 1; }
    if (duckdb_connect(db, &con) == DuckDBError) { fprintf(stderr, "connect failed\n"); return 1; }

    char pragma[64];
    snprintf(pragma, sizeof pragma, "PRAGMA threads=%d;", threads);
    run_sql(con, "pragma", pragma);

    printf("== %s : rows=%ld iters=%d threads=%d (duckdb %s) ==\n",
           label, rows, iters, threads, duckdb_library_version());
    fflush(stdout);

    // Data generation (timed once; deterministic so every build does identical work).
    char gen[512];
    snprintf(gen, sizeof gen,
        "CREATE TABLE t AS SELECT i AS id, (i * 2654435761) %% 4096 AS g, "
        "(i %% 1000)::DOUBLE AS v FROM range(%ld) t(i);", rows);
    double a = now_ms();
    run_sql(con, "datagen", gen);
    printf("%-12s %9.1f ms (once)\n", "datagen", now_ms() - a);
    fflush(stdout);

    run_sql(con, "warmup", "SELECT count(*), sum(v) FROM t;"); // prime caches (untimed)

    timed(con, "groupby",   "SELECT g, count(*), sum(v), avg(v), min(v), max(v) FROM t GROUP BY g;", iters);
    timed(con, "filter",    "SELECT count(*), sum(v) FROM t WHERE g < 100;", iters);
    timed(con, "sort_topn", "SELECT id FROM t ORDER BY v DESC, id LIMIT 100;", iters);
    timed(con, "join",      "SELECT count(*) FROM t JOIN (SELECT DISTINCT g FROM t WHERE g < 64) d USING (g);", iters);

    duckdb_disconnect(&con);
    duckdb_close(&db);
    return 0;
}
