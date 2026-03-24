/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useMemo } from 'react';
import { 
  Menu, 
  Search, 
  Barcode, 
  Plus, 
  AlertTriangle, 
  Package, 
  XCircle, 
  ShoppingCart, 
  CreditCard,
  ChevronLeft
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { MOCK_PRODUCTS } from './constants';
import { Product, CartItem } from './types';

export default function App() {
  const [searchQuery, setSearchQuery] = useState('');
  const [cart, setCart] = useState<CartItem[]>([]);
  const [isCartOpen, setIsCartOpen] = useState(false);

  const filteredProducts = useMemo(() => {
    return MOCK_PRODUCTS.filter(product => 
      product.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      product.brand.toLowerCase().includes(searchQuery.toLowerCase()) ||
      product.category.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }, [searchQuery]);

  const addToCart = (product: Product) => {
    if (product.status === 'out') return;
    
    setCart(prev => {
      const existing = prev.find(item => item.id === product.id);
      if (existing) {
        return prev.map(item => 
          item.id === product.id ? { ...item, quantity: item.quantity + 1 } : item
        );
      }
      return [...prev, { ...product, quantity: 1 }];
    });
  };

  const removeFromCart = (productId: string) => {
    setCart(prev => prev.filter(item => item.id !== productId));
  };

  const totalAmount = cart.reduce((acc, item) => acc + item.price * item.quantity, 0);

  return (
    <div className="min-h-screen bg-surface flex flex-col">
      {/* Header */}
      <header className="fixed top-0 w-full z-50 h-16 bg-primary text-on-primary shadow-lg flex items-center justify-between px-4">
        <div className="flex items-center gap-4">
          <button className="p-2 hover:bg-primary-container rounded-full transition-colors">
            <Menu size={24} />
          </button>
          <h1 className="font-headline font-bold text-lg tracking-tight">Abastecimiento El Torreón</h1>
        </div>
        <button className="p-2 hover:bg-primary-container rounded-full transition-colors">
          <Search size={24} />
        </button>
      </header>

      {/* Main Content */}
      <main className="pt-24 pb-32 px-4 max-w-5xl mx-auto w-full flex-grow">
        {/* Search & Actions */}
        <section className="mb-8 space-y-4">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="relative flex-grow">
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant" size={20} />
              <input 
                type="text"
                placeholder="Filtrar por descripción o marca..."
                className="w-full pl-12 pr-4 py-4 bg-surface-container-highest border-none rounded-lg focus:ring-2 focus:ring-primary focus:bg-surface-container-lowest transition-all font-sans text-on-surface"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
            <button className="bg-primary hover:bg-primary-container text-on-primary px-6 py-4 rounded-lg font-headline font-bold flex items-center justify-center gap-2 shadow-lg active:scale-95 transition-all">
              <Barcode size={20} />
              Escanear Código
            </button>
          </div>
        </section>

        {/* Product Grid */}
        <section className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {filteredProducts.map((product) => (
            <ProductCard key={product.id} product={product} onAdd={() => addToCart(product)} />
          ))}
        </section>

        {filteredProducts.length === 0 && (
          <div className="text-center py-20 text-on-surface-variant">
            <Package size={48} className="mx-auto mb-4 opacity-20" />
            <p className="font-headline font-bold">No se encontraron productos</p>
          </div>
        )}
      </main>

      {/* Bottom Bar */}
      <nav className="fixed bottom-0 w-full z-40 h-20 bg-primary text-on-primary shadow-[0_-4px_12px_rgba(0,0,0,0.1)] flex justify-around items-center px-6">
        <div className="flex flex-col items-center opacity-90">
          <CreditCard size={20} className="mb-1" />
          <span className="text-sm font-semibold">Total: ${totalAmount.toLocaleString('es-AR', { minimumFractionDigits: 2 })}</span>
        </div>
        <button 
          onClick={() => setIsCartOpen(true)}
          className="flex flex-col items-center bg-white/20 rounded-xl px-6 py-2 hover:bg-white/10 transition-all active:scale-95 relative"
        >
          <ShoppingCart size={20} className="mb-1" />
          <span className="text-sm font-semibold">Ver Carrito</span>
          {cart.length > 0 && (
            <span className="absolute -top-1 -right-1 bg-white text-primary text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center shadow-md">
              {cart.reduce((acc, item) => acc + item.quantity, 0)}
            </span>
          )}
        </button>
      </nav>

      {/* Cart Drawer */}
      <AnimatePresence>
        {isCartOpen && (
          <>
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setIsCartOpen(false)}
              className="fixed inset-0 bg-black/40 z-[60] backdrop-blur-sm"
            />
            <motion.div 
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 25, stiffness: 200 }}
              className="fixed right-0 top-0 h-full w-full max-w-md bg-surface z-[70] shadow-2xl flex flex-col"
            >
              <div className="p-4 border-b flex items-center gap-4 bg-primary text-on-primary">
                <button onClick={() => setIsCartOpen(false)} className="p-2 hover:bg-white/10 rounded-full">
                  <ChevronLeft size={24} />
                </button>
                <h2 className="font-headline font-bold text-lg">Tu Carrito</h2>
              </div>
              
              <div className="flex-grow overflow-y-auto p-4 space-y-4">
                {cart.length === 0 ? (
                  <div className="text-center py-20 text-on-surface-variant">
                    <ShoppingCart size={48} className="mx-auto mb-4 opacity-20" />
                    <p className="font-headline font-bold">El carrito está vacío</p>
                  </div>
                ) : (
                  cart.map(item => (
                    <div key={item.id} className="bg-surface-container-lowest p-4 rounded-lg flex justify-between items-center shadow-sm">
                      <div>
                        <h4 className="font-bold text-on-surface">{item.name}</h4>
                        <p className="text-xs text-on-surface-variant">{item.brand} x {item.quantity}</p>
                        <p className="text-sm font-bold text-primary mt-1">
                          ${(item.price * item.quantity).toLocaleString('es-AR', { minimumFractionDigits: 2 })}
                        </p>
                      </div>
                      <button 
                        onClick={() => removeFromCart(item.id)}
                        className="p-2 text-error hover:bg-error-container rounded-full transition-colors"
                      >
                        <XCircle size={20} />
                      </button>
                    </div>
                  ))
                )}
              </div>

              <div className="p-6 bg-surface-container-lowest border-t space-y-4">
                <div className="flex justify-between items-center">
                  <span className="font-headline font-bold text-on-surface-variant">Total</span>
                  <span className="text-2xl font-headline font-extrabold text-primary">
                    ${totalAmount.toLocaleString('es-AR', { minimumFractionDigits: 2 })}
                  </span>
                </div>
                <button className="w-full bg-primary text-on-primary py-4 rounded-lg font-headline font-bold shadow-lg hover:bg-primary-container transition-colors disabled:opacity-50 disabled:cursor-not-allowed" disabled={cart.length === 0}>
                  Confirmar Pedido
                </button>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}

const ProductCard: React.FC<{ product: Product, onAdd: () => void }> = ({ product, onAdd }) => {
  const isOut = product.status === 'out';
  const isLow = product.status === 'low';

  return (
    <motion.div 
      layout
      className={`bg-surface-container-lowest p-5 rounded-lg border border-primary/10 shadow-sm hover:shadow-md transition-shadow group relative overflow-hidden flex flex-col ${isOut ? 'opacity-80 grayscale-[0.5]' : ''}`}
    >
      <div className="space-y-1 mb-4">
        <span className="block text-[10px] uppercase tracking-widest text-on-surface-variant font-bold">{product.category}</span>
        <h3 className="font-headline font-extrabold text-xl text-on-surface leading-tight">{product.name}</h3>
        <div className="flex flex-wrap gap-x-3 gap-y-1 mt-1">
          <span className="text-xs font-semibold text-primary">MARCA: {product.brand}</span>
          <span className="text-xs font-medium text-on-surface-variant">PROVEEDOR: {product.supplier}</span>
        </div>
      </div>

      <div className="mt-auto flex justify-between items-end">
        <div className="space-y-1">
          <span className="text-[10px] font-bold text-on-surface-variant uppercase">Precio Unitario</span>
          <div className="text-2xl font-headline font-extrabold text-on-surface">
            <span className="text-sm align-top mt-1 inline-block mr-0.5">$</span>
            {product.price.toLocaleString('es-AR', { minimumFractionDigits: 2 })}
          </div>
        </div>
        <button 
          onClick={onAdd}
          disabled={isOut}
          className={`w-12 h-12 rounded-lg flex items-center justify-center shadow-md transition-all active:scale-90 ${
            isOut ? 'bg-surface-container-highest text-on-surface-variant cursor-not-allowed' : 'bg-primary text-on-primary hover:bg-primary-container'
          }`}
        >
          {isOut ? <XCircle size={24} /> : <Plus size={24} strokeWidth={3} />}
        </button>
      </div>

      <div className="mt-4 pt-4 border-t border-surface-container flex items-center gap-2">
        {isOut ? (
          <>
            <XCircle size={16} className="text-error fill-error/20" />
            <span className="text-xs font-extrabold text-error">SIN STOCK</span>
          </>
        ) : isLow ? (
          <>
            <AlertTriangle size={16} className="text-primary fill-primary/20" />
            <span className="text-xs font-bold text-primary">{product.stock} unidades (STOCK BAJO)</span>
          </>
        ) : (
          <>
            <Package size={16} className="text-tertiary-container fill-tertiary-container/20" />
            <span className="text-xs font-bold text-on-surface-variant">{product.stock} unidades disponibles</span>
          </>
        )}
      </div>
    </motion.div>
  );
}
