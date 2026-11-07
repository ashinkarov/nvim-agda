module Case where

data 𝔹 : Set where
  tt ff : 𝔹

module Inner where
  f : 𝔹 → 𝔹
  f x = {! x !}

  k : 𝔹 → 𝔹
  k = λ where
    x → {! x !}

l : 𝔹 → 𝔹 → 𝔹
l = λ { tt y → {! y !} ; ff y → y }

m : 𝔹 → 𝔹 → 𝔹
m = λ { tt y → y ; ff y → {! y !} }
