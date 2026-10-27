/-! An assumption, to test conditional results (D68). -/

namespace Toy.Defs.Assumption

/-- A stand-in for an assumption taken from the literature. Source: none; this is a test. -/
def AddZero : Prop := ∀ n : Nat, n + 0 = n

end Toy.Defs.Assumption
