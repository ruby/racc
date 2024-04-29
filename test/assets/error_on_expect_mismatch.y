class E
  expect 0
  error_on_expect_mismatch
rule
  list: inlist inlist
  inlist:
        | A
end
