module Warnings where

data 𝔹 : Set where
  tt ff : 𝔹

f : 𝔹 → 𝔹
f x = f x

g : 𝔹
g = tt tt
