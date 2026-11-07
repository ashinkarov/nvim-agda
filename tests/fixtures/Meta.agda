module Meta where

data 𝔹 : Set where
  tt ff : 𝔹

postulate
  P : 𝔹 → Set
  p : P _
