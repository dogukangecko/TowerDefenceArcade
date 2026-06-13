/** Ürün etkisini insan-okur Türkçe etikete çevirir. */
export function formatEffect(effectType: string, effectValue: number): string {
  switch (effectType) {
    case "none":
      return "—";
    case "startGold":
      return `+${effectValue} başlangıç altını`;
    case "towerDamage":
      return `+%${Math.round(effectValue * 100)} kule hasarı`;
    case "extraLives":
      return `+${effectValue} can`;
    default:
      return `${effectType}: ${effectValue}`;
  }
}

/** Altın fiyatını 🪙 rozetiyle biçimler. */
export function formatPrice(priceGold: number): string {
  return `🪙 ${priceGold.toLocaleString("tr-TR")}`;
}

/** tr-TR tarih+saat biçimi (dashboard "son yayın" kartı). */
export function formatDateTR(date: Date): string {
  return new Intl.DateTimeFormat("tr-TR", {
    dateStyle: "long",
    timeStyle: "short",
  }).format(date);
}
