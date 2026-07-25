// Supabase Edge Function: paymongo-webhook
// Deno runtime
// Deploy with: supabase functions deploy paymongo-webhook
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.1"

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '' // Need service role to bypass RLS if necessary
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Parse PayMongo webhook payload
    const payload = await req.json()

    // E.g., event type is 'payment.paid'
    if (payload.data?.attributes?.type === 'payment.paid') {
      const paymentId = payload.data.attributes.data.id

      // Find the response
      const { data: responses, error: fetchError } = await supabase
        .from('community_check_responses')
        .select('*')
        .eq('payment_id', paymentId)
        
      if (fetchError) throw fetchError
      
      if (responses && responses.length > 0) {
        const response = responses[0]
        
        // Update to paid
        const { error: updateError } = await supabase
          .from('community_check_responses')
          .update({
            payment_status: 'paid',
            is_accepted: true,
          })
          .eq('id', response.id)

        if (updateError) throw updateError

        // Send notification to responder
        const { error: notifError } = await supabase.from('notifications').insert({
          user_id: response.user_id,
          title: 'You received a tip!',
          body: `Your community check response was accepted and you were rewarded ₱${response.tip_amount}!`,
          type: 'tip_received',
          reference_id: response.check_id
        })
        
        if (notifError) console.error('Notification error:', notifError)
      }
    }

    return new Response('Webhook processed', { status: 200 })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 400 })
  }
})
