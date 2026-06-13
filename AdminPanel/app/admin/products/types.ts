/** Server component'ten client'a geçirilen düz ürün nesnesi. */
export type ProductDTO = {
  id: string;
  name: string;
  desc: string;
  icon: string;
  priceGold: number;
  effectType: string;
  effectValue: number;
  premium: boolean;
  status: string;
  kind: string;
  assetKey: string | null;
};
