module Basic where

data 𝔹 : Set where
  tt ff : 𝔹

not : 𝔹 → 𝔹
not x = {! x !}

id′ : 𝔹 → 𝔹
id′ = λ x → ?

pick : 𝔹 → 𝔹 → 𝔹
pick 名前 y = ?
