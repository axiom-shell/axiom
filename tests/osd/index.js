.pragma library
// The OSD's timelines (tst_OSDSystems runs them): one file of rows per
// system, by its name, and Cross for rows across systems. A file whose
// system has no folder yet is skipped, visibly. The row format is
// docs/dev/features/osd.md › Engine › Timelines.
.import "Caffeine.js" as Caffeine
.import "Cross.js" as Cross

var files = {
  "Caffeine": Caffeine.rows,
  "Cross": Cross.rows
};
