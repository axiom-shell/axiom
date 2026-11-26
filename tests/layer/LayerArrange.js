.pragma library
// LayerArrange's contract rows (docs/dev/core/engines.md › The row format):
// where surfaces are placed, how the compositor's list corrects them and
// which windows may show, one row per decision.

var rows = [
  {
    "id": "LY-01",
    "why": "a reserving top bar takes its zone from the top edge",
    "call": "arrange",
    "fixture": "topBar30",
    "expect": {
      "DP-1": {
        "layers": [
          {
            "x": 0,
            "y": 0,
            "width": 1920,
            "height": 30,
            "rule": "reservingFirstByLayer"
          }
        ],
        "reserved": {
          "top": 30
        }
      }
    }
  },
  {
    "id": "LY-02",
    "why": "where the compositor keeps the order, order decides, then map order",
    "call": "arrange",
    "fixture": "twoTopBars",
    "with": {
      "ordered": true
    },
    "expect": {
      "DP-1": {
        "layers": [
          {
            "id": 2,
            "y": 0,
            "rule": "orderThenMapOrder"
          },
          {
            "id": 1,
            "y": 30
          }
        ]
      }
    }
  },
  {
    "id": "LY-03",
    "why": "where the compositor doesn't keep the order, map order decides",
    "call": "arrange",
    "fixture": "twoTopBars",
    "expect": {
      "DP-1": {
        "layers": [
          {
            "id": 1,
            "y": 0,
            "rule": "mapOrderDecides"
          },
          {
            "id": 2,
            "y": 30
          }
        ]
      }
    }
  },
  {
    "id": "LY-04",
    "why": "a surface with zone -1 ignores what others reserve",
    "call": "arrange",
    "fixture": "topBar30",
    "with": {
      "surfaces": [
        {
          "id": 1,
          "outputName": "DP-1",
          "namespace": "axiom-bar",
          "layer": "top",
          "order": 5,
          "seq": 1,
          "anchors": {
            "top": true,
            "left": true,
            "right": true,
            "bottom": false
          },
          "margins": {},
          "width": 0,
          "height": 30,
          "zone": 30
        },
        {
          "id": 2,
          "outputName": "DP-1",
          "namespace": "axiom-menu",
          "layer": "top",
          "order": 7,
          "seq": 2,
          "anchors": {
            "top": true,
            "left": true,
            "right": true,
            "bottom": true
          },
          "margins": {},
          "width": 0,
          "height": 0,
          "zone": -1
        }
      ]
    },
    "expect": {
      "DP-1": {
        "layers": [
          {
            "id": 1
          },
          {
            "id": 2,
            "x": 0,
            "y": 0,
            "width": 1920,
            "height": 1080,
            "rule": "zoneMinusOneIgnoresReserved"
          }
        ]
      }
    }
  },
  {
    "id": "LY-05",
    "why": "a reported rect off by 2 px becomes a correction",
    "call": "correctionsOf",
    "fixture": "reportedShifted",
    "expect": {
      "corrections": {
        "1": {
          "dx": 2,
          "dy": 0,
          "dw": 0,
          "dh": 0,
          "rule": "differenceIsCorrection"
        }
      },
      "misses": {
        "$count": 1
      }
    }
  },
  {
    "id": "LY-06",
    "why": "equal again, a window has no correction (equalDropsCorrection)",
    "call": "correctionsOf",
    "fixture": "reportedShifted",
    "with": {
      "reported": {
        "DP-1": {
          "layers": [
            {
              "namespace": "axiom-bar",
              "x": 0,
              "y": 0,
              "w": 1920,
              "h": 30
            }
          ]
        }
      },
      "current": {
        "1": {
          "dx": 2,
          "dy": 0,
          "dw": 0,
          "dh": 0,
          "rule": "differenceIsCorrection"
        }
      }
    },
    "expect": {
      "corrections": {
        "1": {
          "$absent": true
        }
      },
      "misses": {
        "$count": 0
      }
    }
  },
  {
    "id": "LY-07",
    "why": "an unmapped window keeps its last correction and a window that is gone loses it",
    "call": "correctionsOf",
    "fixture": "reportedShifted",
    "with": {
      "mappedIds": [],
      "liveIds": [
        1
      ],
      "current": {
        "1": {
          "dx": 2,
          "dy": 0,
          "dw": 0,
          "dh": 0,
          "rule": "differenceIsCorrection"
        },
        "2": {
          "dx": 1,
          "dy": 1,
          "dw": 0,
          "dh": 0,
          "rule": "differenceIsCorrection"
        }
      }
    },
    "expect": {
      "corrections": {
        "1": {
          "rule": "keptWhileUnmapped"
        },
        "2": {
          "$absent": true
        }
      }
    }
  },
  {
    "id": "LY-08",
    "why": "a window shows once every earlier-ordered peer that shows is mapped",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "a",
          "outputName": "DP-1",
          "layer": "top",
          "order": 5,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "b",
          "outputName": "DP-1",
          "layer": "top",
          "order": 4,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "a"
      ],
      "rules": {
        "b": "showsAfterPredecessorsMapped"
      }
    }
  },
  {
    "id": "LY-09",
    "why": "a window already showing stays when another ordered before it starts",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "a",
          "outputName": "DP-1",
          "layer": "top",
          "order": 5,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "b",
          "outputName": "DP-1",
          "layer": "top",
          "order": 4,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": {
        "$count": 2
      },
      "rules": {
        "b": "showingStays"
      }
    }
  },
  {
    "id": "LY-10",
    "why": "out of place where map order stacks: it maps again and is hidden while it does",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "a",
          "outputName": "DP-1",
          "layer": "top",
          "order": 5,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 2
        },
        {
          "id": "b",
          "outputName": "DP-1",
          "layer": "top",
          "order": 4,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "steps": [
      {
        "expect": {
          "remap": [
            "b"
          ],
          "rules": {
            "b": "outOfPlaceRemaps"
          }
        }
      },
      {
        "with": {
          "remappingIds": [
            "b"
          ]
        },
        "expect": {
          "show": [
            "a"
          ],
          "rules": {
            "b": "remappingHidden"
          }
        }
      }
    ]
  },
  {
    "id": "LY-11",
    "why": "a held window stays mapped while not wanted",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "a",
          "outputName": "DP-1",
          "layer": "top",
          "order": 5,
          "rank": 0,
          "rankGroup": "",
          "wanted": false,
          "held": true,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "a"
      ],
      "rules": {
        "a": "heldStaysMapped"
      }
    }
  },
  {
    "id": "LY-12",
    "why": "where the compositor keeps the order, only windows of one order can be out of place",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "a",
          "outputName": "DP-1",
          "layer": "top",
          "order": 5,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 2
        },
        {
          "id": "b",
          "outputName": "DP-1",
          "layer": "top",
          "order": 4,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1
        }
      ],
      "ordered": true,
      "remappingIds": []
    },
    "expect": {
      "remap": {
        "$count": 0
      },
      "rules": {
        "b": "orderedOnlyTiesByMapOrder"
      }
    }
  },
  {
    "id": "LY-13",
    "why": "of one order a higher rank (a border corner) waits for the lower ones (its strips)",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "strip",
          "outputName": "DP-1",
          "layer": "top",
          "order": 0,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "corner",
          "outputName": "DP-1",
          "layer": "top",
          "order": 0,
          "rank": 1,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "strip"
      ],
      "rules": {
        "corner": "rankWithinOrder"
      }
    }
  },
  {
    "id": "LY-25",
    "why": "a modal window is never mapped again, though one ordered before it mapped after it",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "modal",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "popout",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 2
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "remap": [],
      "rules": {
        "modal": "modalNeverRemaps"
      }
    }
  },
  {
    "id": "LY-26",
    "why": "where the compositor keeps the order, a modal window that a window of another order mapped after is in place: no remap, and no modal rule",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "modal",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "popout",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 2
        }
      ],
      "ordered": true,
      "remappingIds": []
    },
    "expect": {
      "remap": [],
      "rules": {
        "modal": "orderedOnlyTiesByMapOrder"
      }
    }
  },
  {
    "id": "LY-32",
    "why": "nothing new shows over a modal window that shows: the OSD and the toast box wait",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "osd",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "notifications",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "polkit"
      ],
      "remap": [],
      "rules": {
        "osd": "waitsUnderModal",
        "notifications": "waitsUnderModal"
      }
    }
  },
  {
    "id": "LY-33",
    "why": "a modal window that is gone holds nothing: the windows that waited show",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": false,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0,
          "modal": true
        },
        {
          "id": "osd",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "notifications",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "osd",
        "notifications"
      ],
      "remap": [],
      "rules": {
        "osd": "showsAfterPredecessorsMapped"
      }
    }
  },
  {
    "id": "LY-34",
    "why": "a modal window still showing but no longer wanted holds its output until it is hidden",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": false,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "osd",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "notifications",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [],
      "remap": [],
      "rules": {
        "osd": "waitsUnderModal"
      }
    }
  },
  {
    "id": "LY-35",
    "why": "a modal window shows once wanted, without waiting for a window ordered before it to map",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "osd",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "screenshot",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0,
          "modal": true
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "osd",
        "screenshot"
      ],
      "rules": {
        "screenshot": "modalShowsAtOnce"
      }
    }
  },
  {
    "id": "LY-36",
    "why": "the modal windows are never mapped again, in whatever order they mapped",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 5,
          "modal": true
        },
        {
          "id": "screenshot",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 3,
          "modal": true
        },
        {
          "id": "powermenu",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "monitor-prompt",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 4,
          "modal": true
        },
        {
          "id": "screen-share-picker",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 2,
          "modal": true
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "polkit",
        "screenshot",
        "powermenu",
        "monitor-prompt",
        "screen-share-picker"
      ],
      "remap": []
    }
  },
  {
    "id": "LY-37",
    "why": "the launcher and the overview wait while the power menu shows on their output",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "powermenu",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "edge-popout",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "workspaces",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "powermenu"
      ],
      "remap": [],
      "rules": {
        "edge-popout": "waitsUnderModal",
        "workspaces": "waitsUnderModal"
      }
    }
  },
  {
    "id": "LY-38",
    "why": "a modal window holds only its own output: the launcher and the overview on another output show",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "powermenu",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "edge-popout",
          "outputName": "DP-2",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "workspaces",
          "outputName": "DP-2",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "powermenu",
        "edge-popout",
        "workspaces"
      ],
      "remap": []
    }
  },
  {
    "id": "LY-39",
    "why": "the launcher and the overview show when the power menu is gone",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "powermenu",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": false,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0,
          "modal": true
        },
        {
          "id": "edge-popout",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "workspaces",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "edge-popout",
        "workspaces"
      ],
      "remap": []
    }
  },
  {
    "id": "LY-40",
    "why": "a modal window wanted in the same pass as another window holds the output at once: the other waits",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "osd",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -10,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        },
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0,
          "modal": true
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "polkit"
      ],
      "remap": [],
      "rules": {
        "osd": "waitsUnderModal",
        "polkit": "modalShowsAtOnce"
      }
    }
  },
  {
    "id": "LY-41",
    "why": "a window of another layer is not held: it opens under the modal window",
    "call": "sequence",
    "input": {
      "entries": [
        {
          "id": "polkit",
          "outputName": "DP-1",
          "layer": "overlay",
          "order": -30,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": true,
          "mapped": true,
          "seq": 1,
          "modal": true
        },
        {
          "id": "menu",
          "outputName": "DP-1",
          "layer": "top",
          "order": 7,
          "rank": 0,
          "rankGroup": "",
          "wanted": true,
          "held": false,
          "showing": false,
          "mapped": false,
          "seq": 0
        }
      ],
      "ordered": false,
      "remappingIds": []
    },
    "expect": {
      "show": [
        "polkit",
        "menu"
      ],
      "remap": []
    }
  },
  {
    "id": "LY-42",
    "why": "a modal window wanted in this pass holds its output before it shows",
    "call": "modalHolds",
    "input": {
      "modal": true,
      "showing": false,
      "wanted": true,
      "held": false
    },
    "expect": true
  },
  {
    "id": "LY-43",
    "why": "a modal window that shows holds its output though no longer wanted",
    "call": "modalHolds",
    "input": {
      "modal": true,
      "showing": true,
      "wanted": false,
      "held": false
    },
    "expect": true
  },
  {
    "id": "LY-44",
    "why": "a modal window neither showing nor wanted holds nothing",
    "call": "modalHolds",
    "input": {
      "modal": true,
      "showing": false,
      "wanted": false,
      "held": false
    },
    "expect": false
  },
  {
    "id": "LY-45",
    "why": "a window that is not modal holds nothing",
    "call": "modalHolds",
    "input": {
      "modal": false,
      "showing": true,
      "wanted": true,
      "held": false
    },
    "expect": false
  }
];
