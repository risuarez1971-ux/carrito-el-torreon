export interface Product {
  id: string;
  category: string;
  name: string;
  brand: string;
  supplier: string;
  price: number;
  stock: number;
  status: 'low' | 'normal' | 'out';
}

export interface CartItem extends Product {
  quantity: number;
}
