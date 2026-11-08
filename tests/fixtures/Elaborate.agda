module Elaborate where

data 𝔹 : Set where
  tt ff : 𝔹

not : 𝔹 → 𝔹
not tt = ff
not ff = tt

x : 𝔹
x = {! not tt !}

y : 𝔹 → 𝔹
y b = {! not (not b) !}
