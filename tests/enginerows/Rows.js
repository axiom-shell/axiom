.pragma library
// The well-formed rows of tst_EngineRows: they run through its two fake
// facades, facadeEcho (an engine facade with a feed) and helperPositional
// (a positional helper); each row pins one rule of the row format.

var rows = [
  {
    "id": "DEMO-01",
    "why": "a subset passes with extra actual keys",
    "call": "echo",
    "input": {
      "value": 1,
      "extra": 2
    },
    "expect": {
      "answer": 1
    }
  },
  {
    "id": "DEMO-02",
    "why": "an array of the same length holds in order",
    "call": "echo",
    "input": {
      "list": [
        {
          "a": 1,
          "b": 2
        },
        {
          "a": 3
        }
      ]
    },
    "expect": {
      "seen": {
        "list": [
          {
            "a": 1
          },
          {
            "a": 3
          }
        ]
      }
    }
  },
  {
    "id": "DEMO-03",
    "why": "$count of an array",
    "call": "echo",
    "input": {
      "list": [
        1,
        2,
        3
      ]
    },
    "expect": {
      "seen": {
        "list": {
          "$count": 3
        }
      }
    }
  },
  {
    "id": "DEMO-04",
    "why": "$count of an object",
    "call": "echo",
    "input": {
      "object": {
        "a": 1,
        "b": 2
      }
    },
    "expect": {
      "seen": {
        "object": {
          "$count": 2
        }
      }
    }
  },
  {
    "id": "DEMO-05",
    "why": "$less",
    "call": "echo",
    "input": {
      "value": 5
    },
    "expect": {
      "answer": {
        "$less": 10
      }
    }
  },
  {
    "id": "DEMO-06",
    "why": "$between",
    "call": "echo",
    "input": {
      "value": 5
    },
    "expect": {
      "answer": {
        "$between": [
          4,
          6
        ]
      }
    }
  },
  {
    "id": "DEMO-07",
    "why": "$absent as a key",
    "call": "echo",
    "input": {
      "value": 5
    },
    "expect": {
      "answer": 5,
      "seen": {
        "nothing": {
          "$absent": true
        }
      }
    }
  },
  {
    "id": "DEMO-08",
    "why": "$absent at the top",
    "call": "maybe",
    "input": {
      "value": 0
    },
    "steps": [
      {
        "expect": {
          "$absent": true
        }
      },
      {
        "with": {
          "value": 4
        },
        "expect": {
          "answer": 4
        }
      }
    ]
  },
  {
    "id": "DEMO-09",
    "why": "with merges objects by key and replaces arrays",
    "call": "echo",
    "input": {
      "o": {
        "a": 1,
        "b": 2
      },
      "list": [
        1,
        2,
        3
      ]
    },
    "with": {
      "o": {
        "b": 9
      },
      "list": [
        7
      ]
    },
    "expect": {
      "seen": {
        "o": {
          "a": 1,
          "b": 9
        },
        "list": [
          7
        ]
      }
    }
  },
  {
    "id": "DEMO-10",
    "why": "with keeps a function value",
    "call": "echo",
    "fixture": "withFunction",
    "with": {
      "value": 2
    },
    "expect": {
      "answer": 2,
      "told": "kept"
    }
  },
  {
    "id": "DEMO-11",
    "why": "steps carry now and prev",
    "call": "echo",
    "input": {
      "value": 1
    },
    "steps": [
      {
        "now": 100,
        "expect": {
          "seen": {
            "now": 100,
            "prev": null
          }
        }
      },
      {
        "with": {
          "value": 2
        },
        "expect": {
          "seen": {
            "now": 100,
            "value": 2,
            "prev": {
              "answer": 1
            }
          }
        }
      },
      {
        "now": 250,
        "expect": {
          "seen": {
            "now": 250,
            "prev": {
              "answer": 2
            }
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-12",
    "why": "a fixture's prev seeds step 0 and is not carried",
    "call": "echo",
    "fixture": "withPrev",
    "steps": [
      {
        "expect": {
          "seen": {
            "value": 5,
            "prev": {
              "answer": 99
            }
          }
        }
      },
      {
        "expect": {
          "seen": {
            "prev": {
              "seen": {
                "prev": {
                  "answer": 99
                }
              }
            }
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-13",
    "why": "an input's prev seeds step 0",
    "call": "echo",
    "input": {
      "value": 6,
      "prev": {
        "answer": 77
      }
    },
    "steps": [
      {
        "expect": {
          "seen": {
            "prev": {
              "answer": 77
            }
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-14",
    "why": "a single call receives the prev key",
    "call": "echo",
    "input": {
      "value": 1,
      "prev": {
        "answer": 5
      }
    },
    "expect": {
      "seen": {
        "prev": {
          "answer": 5
        }
      }
    }
  },
  {
    "id": "DEMO-15",
    "why": "expect null against a call answering null",
    "call": "none",
    "input": {},
    "expect": null
  },
  {
    "id": "DEMO-16",
    "why": "a feed step with no event",
    "call": "watch",
    "input": {
      "watch": {
        "events": []
      }
    },
    "steps": [
      {
        "now": 10,
        "expect": {
          "watch": {
            "events": {
              "$count": 0
            }
          },
          "reduce": null
        }
      }
    ]
  },
  {
    "id": "DEMO-17",
    "why": "a feed step with one event",
    "call": "watch",
    "input": {
      "watch": {
        "events": []
      }
    },
    "steps": [
      {
        "with": {
          "watch": {
            "events": [
              {
                "id": "a"
              }
            ]
          }
        },
        "expect": {
          "reduce": {
            "n": 1,
            "got": {
              "id": "a"
            }
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-18",
    "why": "a feed step with several events, then none",
    "call": "watch",
    "input": {
      "watch": {
        "events": []
      }
    },
    "steps": [
      {
        "now": 40,
        "with": {
          "watch": {
            "events": [
              {
                "id": "a"
              },
              {
                "id": "b"
              },
              {
                "id": "c"
              }
            ]
          }
        },
        "expect": {
          "watch": {
            "seen": {
              "now": 40
            }
          },
          "reduce": {
            "n": 3,
            "got": {
              "id": "c"
            },
            "seen": {
              "now": 40,
              "event": {
                "id": "c"
              }
            }
          }
        }
      },
      {
        "with": {
          "watch": {
            "events": []
          }
        },
        "expect": {
          "reduce": {
            "n": 3,
            "got": {
              "id": "c"
            }
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-19",
    "why": "a feed step with no event keeps a seeded prev",
    "call": "watch",
    "fixture": "feedSeeded",
    "steps": [
      {
        "expect": {
          "reduce": {
            "n": 7
          }
        }
      }
    ]
  },
  {
    "id": "DEMO-20",
    "why": "a feed row with expect and no steps",
    "call": "watch",
    "input": {
      "watch": {
        "events": []
      }
    },
    "with": {
      "watch": {
        "events": [
          {
            "id": "z"
          }
        ]
      }
    },
    "expect": {
      "watch": {
        "events": {
          "$count": 1
        }
      },
      "reduce": {
        "n": 1,
        "got": {
          "id": "z"
        }
      }
    }
  },
  {
    "id": "DEMO-21",
    "why": "args spread into a positional helper",
    "call": "moveItem",
    "args": [
      [
        "a",
        "b",
        "c"
      ],
      0,
      2
    ],
    "expect": [
      "b",
      "c",
      "a"
    ]
  }
];
