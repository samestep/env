#!/usr/bin/env lumo

(require '[lumo.core :as lumo])

(def cson (js/require "cson-parser"))
(def fs (js/require "fs"))

(let [path (first lumo/*command-line-args*)
      file (str (.readFileSync fs path))
      parsed (.parse cson file)
      stringified (str (.stringify cson parsed nil 2) "\n")]
  (.writeFileSync fs path stringified))
