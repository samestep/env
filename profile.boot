(require 'boot.repl)

(swap! boot.repl/*default-dependencies* conj
       '[proto-repl "0.3.1"]
       '[proto-repl-charts "0.3.2"])
