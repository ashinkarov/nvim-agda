module Shadow where

data 𝔹 : Set where
  tt ff : 𝔹

shadow : 𝔹 → 𝔹 → 𝔹
shadow x = λ x → ?
