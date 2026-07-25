// Supabase Edge Function: paymongo-checkout (Sandbox/Mock)
// Deno runtime
// Deploy with: supabase functions deploy paymongo-checkout
//
// This is a mock function that simulates creating a PayMongo checkout link.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseKey)

    const { responseId, amount } = await req.json()

    if (!responseId || !amount) {
      throw new Error('responseId and amount are required')
    }

    // 1. Generate a dummy payment ID
    const dummyPaymentId = 'pay_' + Math.random().toString(36).substr(2, 9)

    // 2. Set the status to 'pending' in the database
    const { error } = await supabase
      .from('community_check_responses')
      .update({
        payment_status: 'pending',
        payment_id: dummyPaymentId,
        tip_amount: amount,
      })
      .eq('id', responseId)

    if (error) throw error

    // 3. Return the dummy sandbox checkout URL
    const dummyUrl = `https://sandbox.paymongo.com/checkout?id=${dummyPaymentId}`

    return new Response(JSON.stringify({ checkout_url: dummyUrl }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
