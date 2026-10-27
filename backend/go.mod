module github.com/axiom-shell/axiom/backend

go 1.26.0

tool (
	golang.org/x/vuln/cmd/govulncheck
	honnef.co/go/tools/cmd/staticcheck
)

require (
	github.com/dop251/goja v0.0.0-20261022125820-07c4b9d6265b
	github.com/fsnotify/fsnotify v1.10.1
	github.com/teambition/rrule-go v1.8.2
	github.com/yuin/gopher-lua v1.1.2
	go.yaml.in/yaml/v3 v3.0.5
	golang.org/x/image v0.47.0
	golang.org/x/sys v0.49.0
)

require (
	github.com/BurntSushi/toml v1.4.1-0.20240526193622-a339e1f7089c // indirect
	github.com/dlclark/regexp2/v2 v2.8.1 // indirect
	github.com/go-sourcemap/sourcemap v2.1.3+incompatible // indirect
	github.com/google/pprof v0.0.0-20230207041349-798e818bf904 // indirect
	golang.org/x/exp/typeparams v0.0.0-20231108232855-2478ac86f678 // indirect
	golang.org/x/mod v0.42.0 // indirect
	golang.org/x/sync v0.24.0 // indirect
	golang.org/x/telemetry v0.0.0-20261010193011-f71dc92da45e // indirect
	golang.org/x/text v0.43.0 // indirect
	golang.org/x/tools v0.52.0 // indirect
	golang.org/x/vuln v1.9.0 // indirect
	honnef.co/go/tools v0.8.2 // indirect
)
