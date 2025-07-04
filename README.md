# Salesforce B2B Pricing Extension

Teste técnico – Everymind – Jul/2025  
Autor: <seu nome>

## ✨ Visão Geral
Implementa uma _Pricing Extension_ para Salesforce B2B Commerce Cloud.  
O preço de cada SKU é calculado dinamicamente por cliente, consultando um endpoint externo e armazenando em Platform Cache (TTL = 5 min).

## 📂 Conteúdo do repositório
| Pasta / Arquivo | Descrição |
|-----------------|-----------|
| `force-app/` | Código Apex e metadados (Remote Site Settings (RSS), Cache, Provider) |
| `README.md` | Este guia |

## 🚀 Como Instalar/Testar

1. **Pré‑requisitos**  
   - Salesforce CLI (`sf`)  
   - Node.js `>= 18`

2. **Clone e abra**  
   ```bash
   git clone https://github.com/conradowander/b2b-pricing-extension.git
   cd b2b-pricing-extension
