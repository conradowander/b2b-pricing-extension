/**
* CustomPricingExtension
* ------------------------------------------------------------
* Extends........: commercestorepricing.PricingService
* Extension Point: Commerce_Domain_Pricing_Service
* Objetivo.......: Calcular preços por cliente, consumindo
*                  endpoint externo e usando Platform Cache.
* ------------------------------------------------------------
*
* PRÉ‑REQUISITOS
* - Remote Site Setting: MockyEndpoint -> https://686526645b5d8d03397fef5b.mockapi.io
* - Platform Cache: PriceCache (org‑cache = 3 MB)
*
* ------------------------------------------------------------
*
* DESENVOLVEDOR / DATA DE CRIAÇÃO
*
* Nome: Wanderson Conrado Lima
* Data criação 03/07/2025
*
**/

global without sharing class CustomPricingExtension extends commercestorepricing.PricingService{

    /* ---------- Configurações ---------- */
    private static final String BASE_URL        = 'https://686526645b5d8d03397fef5b.mockapi.io';
    private static final String RELATIVE_PATH   = '/api/v1/clientes';
    private static final Integer CACHE_TTL_SEC  = 300;   // 5 min
    private static final String CACHE_PARTITION = 'PriceCache';
    private static final String CACHE_PREFIX    = 'PRICE';   // somente letras/números

    /* ---------- DTO interno ---------- */
    private class PriceBundle{
        Decimal listPrice;
        Decimal negotiatedPrice;
        PriceBundle(Decimal lp, Decimal np){
            listPrice       = lp;
            negotiatedPrice = np;
        }
    }

    /* ==========================================================
       MÉTODO PRINCIPAL
    ========================================================= */
    override public commercestorepricing.PricingResponse processPrice(commercestorepricing.PricingRequest req){

        Id accountId = (Id) req.getEffectiveAccountId();
        if(accountId == null){
            return super.processPrice(req);
        }

        Account buyer = [
            SELECT Id, External_Id__c
            FROM   Account
            WHERE  Id = :accountId
            LIMIT  1
        ];

        String clientExtId = buyer.External_Id__c;
        if(String.isBlank(clientExtId)){
            return super.processPrice(req);
        }

        /* ----- Tabela de preços (cache + callout) ----- */
        Map<String,PriceBundle> priceBook = fetchPrices(clientExtId, accountId);

        /* ----- Resolve SKUs dos itens ----- */
        Set<Id> prodIds = new Set<Id>();
        commercestorepricing.PricingRequestItemCollection items = req.getPricingRequestItems();
        
        for(Integer i = 0; i < items.size(); i++){
            prodIds.add(items.get(i).getProductId());
        }

        Map<Id,Product2> prodMap = new Map<Id,Product2>(
            [SELECT Id, SKU__c FROM Product2 WHERE Id IN :prodIds]
        );

        /* ----- Monta resposta ----- */
        commercestorepricing.PricingResponse resp = new commercestorepricing.PricingResponse(req.getCurrencyIsoCode());

        for(Integer i = 0; i < items.size(); i++){
            commercestorepricing.PricingRequestItem it = items.get(i);
            String sku = prodMap.get(it.getProductId())?.SKU__c;

            if(sku != null && priceBook.containsKey(sku)){
                PriceBundle p = priceBook.get(sku);
                resp.addPricingResponseItem(
                    new commercestorepricing.PricingResponseItem(
                        it.getProductId(), null, null,
                        p.listPrice, p.negotiatedPrice
                    )
                );
            }
            else{
                commercestorepricing.PricingResponseItem err =
                    new commercestorepricing.PricingResponseItem(
                        it.getProductId(), null, null, null, null
                    );
                err.setError(
                    'Preço não encontrado para SKU ' + sku,
                    'Price not found for SKU '  + sku
                );
                resp.addPricingResponseItem(err);
            }
        }
        return resp;
    }

    /* ==========================================================
       Helper: busca preços (Cache + Callout)
    ========================================================= */
    private static Map<String,PriceBundle> fetchPrices(String clientExtId, Id accountId){
        
        if(String.isBlank(clientExtId)){
            throw new CalloutException('ExternalId__c do cliente está vazio.');
        }
        
        if(String.isBlank(accountId)){
            throw new cache.InvalidParamException('AccountId inválido ou nulo para uso em cache.');
        }

        String safeAccountId = String.valueOf(accountId).replaceAll('[^a-zA-Z0-9]', '');
        String cacheKey      = CACHE_PREFIX + safeAccountId;

        Cache.OrgPartition part = Cache.Org.getPartition(CACHE_PARTITION);

        /* 1) Cache -------------------------------------------------------- */
        Map<String,PriceBundle> cached = (Map<String,PriceBundle>) part.get(cacheKey);
        
        if(cached != null) return cached;

        /* 2) Callout externo ---------------------------------------------- */
        HttpRequest r = new HttpRequest();
        r.setEndpoint(BASE_URL + RELATIVE_PATH);   // Remote Site Settings
        r.setMethod('GET');

        HttpResponse res = new Http().send(r);

        if(res.getStatusCode() != 200){
            throw new CalloutException('Erro no endpoint externo: ' + res.getStatus());
        }

        /* 3) Parse JSON ---------------------------------------------------- */
        List<Object> root = (List<Object>) JSON.deserializeUntyped(res.getBody());
        Map<String,PriceBundle> result = new Map<String,PriceBundle>();

        for(Object o : root){
            
            Map<String,Object> node = (Map<String,Object>) o;
            
            if(String.valueOf(node.get('id')) == clientExtId){     // ← campo “id”
                
                List<Object> precos = (List<Object>) node.get('precos');
                
                for(Object pObj : precos){
                    Map<String,Object> p = (Map<String,Object>) pObj;
                    String  sku       = (String)  p.get('sku');
                    Decimal listP     = Decimal.valueOf(String.valueOf(p.get('list_price')));
                    Decimal salesP    = Decimal.valueOf(String.valueOf(p.get('sales_price')));
                    result.put(sku, new PriceBundle(listP, salesP));
                }
                break;
            }
        }

        /* 4) Salva no cache ----------------------------------------------- */
        if(!result.isEmpty()){
            part.put(cacheKey, result, CACHE_TTL_SEC);
        }
        return result;
    }
}