CLASS lhc__log DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR _details RESULT result.
    METHODS sendpaymentdetails FOR MODIFY
      IMPORTING keys FOR ACTION _details~sendpaymentdetails.
    METHODS status FOR MODIFY
      IMPORTING keys FOR ACTION _details~status.
    METHODS encrypt FOR DETERMINE ON SAVE
      IMPORTING keys FOR _details~encrypt.

ENDCLASS.

CLASS lhc__log IMPLEMENTATION.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD sendpaymentdetails.
    "Get key ID.
    DATA(key_with_id) = keys.

    "Read and Update The Key details.
    READ ENTITIES OF zr_paymentdetails IN LOCAL MODE
    ENTITY _details
    FIELDS ( zpaymentuuid zpaymentfilereference zfilecontent zpaymentsync zpaymentstatus zencryptedfile )
    WITH CORRESPONDING #( key_with_id )
    RESULT DATA(paymentdetails).

    "Payment Sync Check
    DATA paymentsync.

    "Get Current File content Details
    DATA filecontent TYPE string.

    LOOP AT paymentdetails INTO DATA(paymentdetail).
      filecontent = paymentdetail-zencryptedfile.
      paymentsync = paymentdetail-zpaymentsync.
    ENDLOOP.

    IF paymentsync IS INITIAL AND filecontent IS NOT INITIAL.

      "Create client id and client secret field for pass value runtime via API.
      DATA clientid TYPE string.
      DATA clientsecret TYPE string.

      DATA: lt_data TYPE TABLE OF zconfiguration,
            ls_data TYPE zconfiguration.

      "Select data from a configuration table
      SELECT * FROM zconfiguration WHERE z_id = 'ROOT' INTO TABLE @lt_data.

      IF lt_data IS NOT INITIAL.
        LOOP AT lt_data INTO ls_data.
          clientid = ls_data-z_client_id.
          clientsecret = ls_data-z_client_secret.
        ENDLOOP.
      ENDIF.

      TRY.
          "API call for Post Payment Details.
          DATA(loo_destination_payment) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZPAYMENTAPI_SC'
                               ).
          DATA(loo_http_client_payment) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_payment ).

          DATA(loo_request_payment) = loo_http_client_payment->get_http_request( ).

          loo_request_payment->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/xml' ) ) ).

          DATA bodycontent TYPE string.

          bodycontent = filecontent.

          loo_request_payment->set_text( bodycontent ).


          "API call for Get Refresh Token.
          DATA(lo_destination_getrefershtoken) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZGETREFRESHTOKEN_SC'
                               ).
          DATA(lo_http_client_getrefreshtoken) = cl_web_http_client_manager=>create_by_http_destination( lo_destination_getrefershtoken ).

          DATA(lo_request_getrefreshtoken) = lo_http_client_getrefreshtoken->get_http_request( ).

          lo_request_getrefreshtoken->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/x-www-form-urlencoded' ) ) ).

          lo_request_getrefreshtoken->set_form_fields( VALUE #(
          ( name = 'client_id' value = clientid )
          ( name = 'client_secret' value = clientsecret )
          ( name = 'grant_type' value = 'client_credentials' ) ) ).

          "Execute Call.
          DATA(lo_response_getrefreshtoken) = lo_http_client_getrefreshtoken->execute( if_web_http_client=>post ).

          "Result
          DATA(lv_json_getrefreshtoken) = lo_response_getrefreshtoken->get_text( ).

          "Get Status.
          DATA(statuscode_getrefreshtoken) = lo_response_getrefreshtoken->get_status( )-code.

          IF ( statuscode_getrefreshtoken = 200 ).
            "Extract Response Details.
            DATA:
              BEGIN OF ts_tags,
                access_token TYPE string,
                token_type   TYPE string,
                expires_in   TYPE string,
                scope        TYPE string,
              END OF ts_tags.
            /ui2/cl_json=>deserialize( EXPORTING json = lv_json_getrefreshtoken CHANGING data = ts_tags ) .

            "DATA(accToken) = 'Bearer' && '   ' && ts_tags-access_token.

            CONCATENATE 'Bearer' ts_tags-access_token INTO DATA(acctoken) SEPARATED BY space.

            loo_request_payment->set_header_fields( VALUE #(
            ( name = 'Authorization' value = acctoken ) ) ).

            "Execute Call.
            DATA(loo_response_payment) = loo_http_client_payment->execute( if_web_http_client=>post ).

            "Result
            DATA(lv_json_payment) = loo_response_payment->get_text( ).

            "Get Status.
            DATA(statuscode_payment) = loo_response_payment->get_status( )-code.

            "API call for Post for Decrypt Details.
            DATA(loo_destination_decrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZDECRYPTION_SC'
                                 ).
            DATA(loo_http_client_decrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_decrypt ).

            DATA(loo_request_decrypt) = loo_http_client_decrypt->get_http_request( ).

            loo_request_decrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).

            DATA decryptcontent TYPE string.

            decryptcontent = '{ "EncryptedString" : "' && lv_json_payment && '" }'.

            loo_request_decrypt->set_text( decryptcontent ).

            DATA(lo_response_decrypt) = loo_http_client_decrypt->execute( if_web_http_client=>post ).

            "Result
            DATA(lv_json_decrypt) = lo_response_decrypt->get_text( ).

            "Get Status.
            DATA(statuscode_decrypt) = lo_response_decrypt->get_status( )-code.


            IF ( statuscode_payment = 200 ).

              REPLACE ALL OCCURRENCES OF '\' IN lv_json_decrypt WITH ''.

              DATA removelastlen TYPE i.
              removelastlen = strlen( lv_json_decrypt ).
              removelastlen = removelastlen - 1.
              lv_json_decrypt = lv_json_decrypt+0(removelastlen).

              DATA removefirstlen TYPE i.
              removefirstlen = strlen( lv_json_decrypt ).
              removefirstlen = removefirstlen - 1.
              lv_json_decrypt = lv_json_decrypt+1(removefirstlen).

              DATA(decryptedxml) = cl_abap_conv_codepage=>create_out( )->convert( source = lv_json_decrypt ).
              DATA(ixml_pa) = cl_ixml_core=>create( ).
              DATA(stream_factory_pa) = ixml_pa->create_stream_factory( ).
              DATA(document_pa) = ixml_pa->create_document( ).

              DATA(parser_pa) = ixml_pa->create_parser(
                                 istream = stream_factory_pa->create_istream_xstring( string = decryptedxml )
                                 document = document_pa
                                 stream_factory = stream_factory_pa ).
              DATA(parsing_check) = parser_pa->parse( ).
              IF parsing_check = 0.
                DATA(envelope) = document_pa->get_root_element( ).
                DATA(header) = envelope->get_last_child( ).
                DATA(body) = header->get_last_child( ).
                DATA(headerlist) = body->get_first_child( ).
                DATA messageid TYPE string.
                DATA statuscd TYPE string.
                DATA statusrem TYPE string.
                IF headerlist->get_name(  ) = 'AckHeader'.
                  DATA(headers) = headerlist->get_children( ).
                  DATA(headerslength) = headers->get_length(  ).
                  DATA(k) = 0.
                  WHILE headerslength > k.
                    DATA(headerschild) = headers->get_item( k ).
                    IF headerschild->get_name( ) = 'MessageId'.
                      messageid = headerschild->get_value( ).
                    ELSEIF
                      headerschild->get_name( ) = 'StatusCd'.
                      statuscd = headerschild->get_value( ).
                    ELSEIF
                      headerschild->get_name( ) = 'StatusRem'.
                      statusrem = headerschild->get_value( ).
                    ENDIF.
                    k = k + 1.
                  ENDWHILE.

                  IF statuscd = '008' OR statuscd = '011'.
                    MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                    ENTITY _details
                    UPDATE FIELDS ( zpaymentmessageid zpaymentstatus zpaymentstatuscode )
                    WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                               zpaymentmessageid = messageid
                                               zpaymentstatus = statusrem
                                               zpaymentstatuscode = statuscd
                                               ) ).
                  ELSE.
                    MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                    ENTITY _details
                    UPDATE FIELDS ( zpaymentmessageid zpaymentstatus zpaymentsync zpaymentstatuscode )
                    WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                               zpaymentmessageid = messageid
                                               zpaymentstatus = statusrem
                                               zpaymentsync = 'X'
                                               zpaymentstatuscode = statuscd
                                               ) ).
                  ENDIF.
                ENDIF.
                DATA(payment) = body->get_last_child( ).
                DATA(instrumentlist) = payment->get_children( ).
                DATA(instrumentcount) = instrumentlist->get_length( ).
                DATA(i) = 0.
                WHILE instrumentcount > i.
                  DATA instrefno TYPE string.
                  DATA inststatuscd TYPE string.
                  DATA inststatusrem TYPE string.
                  DATA(j) = 0.
                  DATA(childs) = instrumentlist->get_item( i ).
                  IF childs->get_name(  ) = 'Instrument'.
                    DATA(child) = childs->get_children(  ).
                    DATA(childcount) = child->get_length( ).
                    WHILE childcount > j.
                      DATA(childitemdata) = child->get_item( j ).
                      IF childitemdata->get_name( ) = 'InstRefNo'.
                        instrefno = childitemdata->get_value( ).
                      ELSEIF
                        childitemdata->get_name( ) = 'InstStatusCd'.
                        inststatuscd = childitemdata->get_value( ).
                      ELSEIF
                        childitemdata->get_name( ) = 'InstStatusRem'.
                        inststatusrem = childitemdata->get_value( ).
                      ENDIF.
                      j = j + 1.
                    ENDWHILE.

                    SELECT * FROM zinstrumentlist WHERE z_messageid = @instrefno AND z_payment_uuid = @paymentdetail-zpaymentuuid INTO @DATA(lt_data_instrument).
                      IF lt_data_instrument IS NOT INITIAL.
                        MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _instrumentlog UPDATE FIELDS ( zstatuscode zstatusremark )
                        WITH VALUE #( ( %data-zinstrumentuuid = lt_data_instrument-z_instrument_uuid %data-zstatuscode = inststatuscd   %data-zstatusremark = inststatusrem ) ).
                      ENDIF.
                    ENDSELECT.
                  ENDIF.
                  i = i + 1.
                ENDWHILE.
              ENDIF.

              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_log
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_decrypt zresponsecode = statuscode_payment
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.

            ELSE.
              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_log
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_payment zresponsecode = statuscode_payment
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.
            ENDIF.

          ELSE.
            MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_log
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_getrefreshtoken zresponsecode = statuscode_getrefreshtoken
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.

          ENDIF.

        CATCH cx_http_dest_provider_error.
          " handle exception here.

        CATCH cx_web_http_client_error.
          " handle exception here

      ENDTRY.
    ENDIF.

  ENDMETHOD.

  METHOD status.
    "Get key ID.
    DATA(key_with_id) = keys.

    DATA instruments TYPE TABLE OF zinstrumentlist.

    "Read and Update The Key details.
    READ ENTITIES OF zr_paymentdetails IN LOCAL MODE
    ENTITY _details
    FIELDS ( zpaymentuuid zpaymentfilereference zfilecontent zstatussync zpaymentsync zpaymentstatus zmessagesourcecode zclientcode zpaymentmessageid zpaymentstatuscode )
    WITH CORRESPONDING #( key_with_id )
    RESULT DATA(paymentdetails).

    "Payment and Status Sync Check
    DATA statussync.
    DATA paymentsync.
    DATA paymentstatus TYPE string.
    DATA paymentstatuscode TYPE string.

    LOOP AT paymentdetails INTO DATA(paymentdetail).
      paymentsync = paymentdetail-zpaymentsync.
      statussync = paymentdetail-zstatussync.
      paymentstatus = paymentdetail-zpaymentstatus.
      paymentstatuscode = paymentdetail-zpaymentstatuscode.
    ENDLOOP.

    IF statussync IS INITIAL AND paymentsync IS NOT INITIAL AND ( paymentstatuscode = '000' OR paymentstatuscode = '005' ).

      "Create client id and client secret field for pass value runtime via API.
      DATA clientid TYPE string.
      DATA clientsecret TYPE string.

      DATA: lt_data TYPE TABLE OF zconfiguration,
            ls_data TYPE zconfiguration.

      "Select data from a configuration table
      SELECT * FROM zconfiguration WHERE z_id = 'ROOT' INTO TABLE @lt_data.

      IF lt_data IS NOT INITIAL.
        LOOP AT lt_data INTO ls_data.
          clientid = ls_data-z_client_id.
          clientsecret = ls_data-z_client_secret.
        ENDLOOP.
      ENDIF.

      TRY.
          "API call for Post Payment Details.
          DATA(loo_destination_status) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZSTATUSAPI_SC'
                               ).
          DATA(loo_http_client_status) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_status ).

          DATA(loo_request_status) = loo_http_client_status->get_http_request( ).

          loo_request_status->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/xml' ) ) ).

          DATA lv_short_time_stamp TYPE timestampl.
          GET TIME STAMP FIELD lv_short_time_stamp.

          DATA bodycontent TYPE string.

          bodycontent = '<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:rev="http://www.kotak.com/schemas/CMS_Generic/Reversal_Request.xsd">' &&
                        '<soap:Header/>' && '<soap:Body>' && '<rev:Reversal>' && '<rev:Header>' && '<rev:Req_Id>' && paymentdetail-zpaymentmessageid && '</rev:Req_Id>' &&
                        '<rev:Msg_Src>' && paymentdetail-zmessagesourcecode && '</rev:Msg_Src>' && '<rev:Client_Code>' && paymentdetail-zclientcode && '</rev:Client_Code>' &&
                        '<rev:Date_Post>' && lv_short_time_stamp && '+5:30' && '</rev:Date_Post>' &&
                        '</rev:Header><rev:Details><!--Zero or more repetitions:-->' && '<rev:Msg_Id>' && paymentdetail-zpaymentmessageid &&
                        '</rev:Msg_Id>' && '</rev:Details>' && '</rev:Reversal></soap:Body></soap:Envelope>'.

          DATA(xs) = cl_abap_conv_codepage=>create_out( codepage = `UTF-8` )->convert( bodycontent ).

          "API call for Post for Encrypt Details.
          DATA(loo_destination_encrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZENCRYPTION_SC'
                               ).
          DATA(loo_http_client_encrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_encrypt ).

          DATA(loo_request_encrypt) = loo_http_client_encrypt->get_http_request( ).

          loo_request_encrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).


          bodycontent = '{ "x_string" : "' && xs && '" }'.

          loo_request_encrypt->set_text( bodycontent ).

          DATA(lo_response_encrypt) = loo_http_client_encrypt->execute( if_web_http_client=>post ).

          "Result
          DATA(lv_json_encrypt) = lo_response_encrypt->get_text( ).

          "Get Status.
          DATA(statuscode_encrypt) = lo_response_encrypt->get_status( )-code.

          IF ( statuscode_encrypt = 200 ).
            "Extract Response Details.
            DATA:
              BEGIN OF encryption_tags,
                statuscode TYPE string,
                body       TYPE string,
              END OF encryption_tags.
            /ui2/cl_json=>deserialize( EXPORTING json = lv_json_encrypt CHANGING data = encryption_tags ) .
          ENDIF.

          loo_request_status->set_text( encryption_tags-body ).

          "API call for Get Refresh Token.
          DATA(lo_destination_getrefershtoken) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZGETREFRESHTOKEN_SC'
                               ).
          DATA(lo_http_client_getrefreshtoken) = cl_web_http_client_manager=>create_by_http_destination( lo_destination_getrefershtoken ).

          DATA(lo_request_getrefreshtoken) = lo_http_client_getrefreshtoken->get_http_request( ).

          lo_request_getrefreshtoken->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/x-www-form-urlencoded' ) ) ).

          lo_request_getrefreshtoken->set_form_fields( VALUE #(
          ( name = 'client_id' value = clientid )
          ( name = 'client_secret' value = clientsecret )
          ( name = 'grant_type' value = 'client_credentials' ) ) ).

          "Execute Call.
          DATA(lo_response_getrefreshtoken) = lo_http_client_getrefreshtoken->execute( if_web_http_client=>post ).

          "Result
          DATA(lv_json_getrefreshtoken) = lo_response_getrefreshtoken->get_text( ).

          "Get Status.
          DATA(statuscode_getrefreshtoken) = lo_response_getrefreshtoken->get_status( )-code.

          IF ( statuscode_getrefreshtoken = 200 ).
            "Extract Response Details.
            DATA:
              BEGIN OF ts_tags,
                access_token TYPE string,
                token_type   TYPE string,
                expires_in   TYPE string,
                scope        TYPE string,
              END OF ts_tags.
            /ui2/cl_json=>deserialize( EXPORTING json = lv_json_getrefreshtoken CHANGING data = ts_tags ) .

            "DATA(accToken) = 'Bearer' && '   ' && ts_tags-access_token.

            CONCATENATE 'Bearer' ts_tags-access_token INTO DATA(acctoken) SEPARATED BY space.

            loo_request_status->set_header_fields( VALUE #(
            ( name = 'Authorization' value = acctoken ) ) ).

            "Execute Call.
            DATA(loo_response_status) = loo_http_client_status->execute( if_web_http_client=>post ).

            "Result
            DATA(lv_json_status) = loo_response_status->get_text( ).

            "Get Status.
            DATA(statuscode_status) = loo_response_status->get_status( )-code.

            "API call for Post for Decrypt Details.
            DATA(loo_destination_decrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZDECRYPTION_SC'
                                 ).
            DATA(loo_http_client_decrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_decrypt ).

            DATA(loo_request_decrypt) = loo_http_client_decrypt->get_http_request( ).

            loo_request_decrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).

            DATA decryptcontent TYPE string.

            decryptcontent = '{ "EncryptedString" : "' && lv_json_status && '" }'.

            loo_request_decrypt->set_text( decryptcontent ).

            DATA(lo_response_decrypt) = loo_http_client_decrypt->execute( if_web_http_client=>post ).

            "Result
            DATA(lv_json_decrypt) = lo_response_decrypt->get_text( ).

            "Get Status.
            DATA(statuscode_decrypt) = lo_response_decrypt->get_status( )-code.


            IF ( statuscode_status = 200 ).

              REPLACE ALL OCCURRENCES OF '\' IN lv_json_decrypt WITH ''.

              DATA removelastlen TYPE i.
              removelastlen = strlen( lv_json_decrypt ).
              removelastlen = removelastlen - 1.
              lv_json_decrypt = lv_json_decrypt+0(removelastlen).

              DATA removefirstlen TYPE i.
              removefirstlen = strlen( lv_json_decrypt ).
              removefirstlen = removefirstlen - 1.
              lv_json_decrypt = lv_json_decrypt+1(removefirstlen).

              DATA(decryptedxml) = cl_abap_conv_codepage=>create_out( )->convert( source = lv_json_decrypt ).
              DATA(ixml_pa) = cl_ixml_core=>create( ).
              DATA(stream_factory_pa) = ixml_pa->create_stream_factory( ).
              DATA(document_pa) = ixml_pa->create_document( ).

              DATA(parser_pa) = ixml_pa->create_parser(
                                 istream = stream_factory_pa->create_istream_xstring( string = decryptedxml )
                                 document = document_pa
                                 stream_factory = stream_factory_pa ).
              DATA(parsing_check) = parser_pa->parse( ).
              IF parsing_check = 0.
                DATA(envelope) = document_pa->get_root_element( ).
                DATA(body) = envelope->get_last_child( ).
                DATA(header) = body->get_last_child( ).
                DATA(detailslist) = header->get_last_child(  ).
                IF detailslist->get_name(  ) = 'Details'.
                  DATA(details) = detailslist->get_children( ).
                  DATA(detailslength) = details->get_length(  ).
                  DATA(i) = 0.
                  WHILE detailslength > i.
                    DATA msg_id TYPE string.
                    DATA status_code TYPE string.
                    DATA status_desc TYPE string.
                    DATA(detailschild) = details->get_item( i ).
                    DATA(detail) = detailschild->get_children(  ).
                    DATA(detaillength) = detail->get_length(  ).
                    DATA(j) = 0.
                    WHILE detaillength > j.
                      DATA(detailitemdata) = detail->get_item( j ).
                      IF detailitemdata->get_name( ) = 'InstRefNo'.
                        msg_id = detailitemdata->get_value( ).
                      ELSEIF
                        detailitemdata->get_name( ) = 'Status_Code'.
                        status_code = detailitemdata->get_value( ).
                      ELSEIF
                        detailitemdata->get_name( ) = 'Status_Desc'.
                        status_desc = detailitemdata->get_value( ).
                      ENDIF.
                      j = j + 1.
                    ENDWHILE.

                    SELECT * FROM zinstrumentlist WHERE z_messageid = @msg_id AND z_payment_uuid = @paymentdetail-zpaymentuuid INTO @DATA(lt_data_instrument).
                      IF lt_data_instrument IS NOT INITIAL.
                        MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _instrumentlog UPDATE FIELDS ( zstatuscode zstatusremark )
                        WITH VALUE #( ( %data-zinstrumentuuid = lt_data_instrument-z_instrument_uuid %data-zstatuscode = status_code   %data-zstatusremark = status_desc ) ).
                        lt_data_instrument-z_statuscode = status_code.
                        lt_data_instrument-z_statusremark = status_desc.
                        APPEND lt_data_instrument TO instruments.
                      ENDIF.
                    ENDSELECT.

                    i = i + 1.
                  ENDWHILE.
                  MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                    ENTITY _details
                    UPDATE FIELDS ( zstatussync )
                    WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky zstatussync = 'X' ) ).
                ENDIF.
              ENDIF.

              DATA totalinstrumentlistdetails TYPE TABLE OF zinstrumentlist.
              DATA totalinstrument TYPE i.

              "Total Instrument list details.
              SELECT * FROM zinstrumentlist WHERE  z_payment_uuid = @paymentdetail-zpaymentuuid INTO TABLE @totalinstrumentlistdetails.
              IF totalinstrumentlistdetails IS NOT INITIAL.
                totalinstrument = lines( totalinstrumentlistdetails ).
              ENDIF.

              IF instruments IS NOT INITIAL.

                DATA currentinstrument TYPE i.

                DATA(processedlist) = instruments.
                DATA(inprocesslist_c) = instruments.
                DATA(inprocesslist_pa) = instruments.
                DATA(inprocesslist_ps) = instruments.
                DATA(inprocesslist_0) = instruments.
                DATA(inprocesslist_empty) = instruments.

                DELETE inprocesslist_c WHERE z_payment_uuid EQ paymentdetail-zpaymentuuid AND z_statuscode NE 'C'.

                IF inprocesslist_c IS NOT INITIAL.
                  currentinstrument = lines( inprocesslist_c ).
                  IF currentinstrument IS NOT INITIAL.
                    MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                          ENTITY _details
                          UPDATE FIELDS ( zbankprocessedstatus zstatussync )
                          WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                         zbankprocessedstatus = 'Few Instruments are In-process.'
                                                         zstatussync = ''
                                                         ) ).
                  ENDIF.
                ELSE.
                  DELETE inprocesslist_pa WHERE z_payment_uuid EQ paymentdetail-zpaymentuuid AND z_statuscode NE 'PA'.

                  IF inprocesslist_pa IS NOT INITIAL.
                    currentinstrument = lines( inprocesslist_pa ).
                    IF currentinstrument IS NOT INITIAL.
                      MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                            ENTITY _details
                            UPDATE FIELDS ( zbankprocessedstatus zstatussync )
                            WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                           zbankprocessedstatus = 'Few Instruments are In-process.'
                                                           zstatussync = ''
                                                           ) ).
                    ENDIF.
                  ELSE.
                    DELETE inprocesslist_ps WHERE z_payment_uuid EQ paymentdetail-zpaymentuuid AND z_statuscode NE 'PS'.

                    IF inprocesslist_ps IS NOT INITIAL.
                      currentinstrument = lines( inprocesslist_ps ).
                      IF currentinstrument IS NOT INITIAL.
                        MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                              ENTITY _details
                              UPDATE FIELDS ( zbankprocessedstatus zstatussync )
                              WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                             zbankprocessedstatus = 'Few Instruments are In-process.'
                                                             zstatussync = ''
                                                             ) ).
                      ENDIF.
                    ELSE.
                      DELETE inprocesslist_0 WHERE z_payment_uuid EQ paymentdetail-zpaymentuuid AND z_statuscode NE 'O'.

                      IF inprocesslist_0 IS NOT INITIAL.
                        currentinstrument = lines( inprocesslist_0 ).
                        IF currentinstrument IS NOT INITIAL.
                          MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                                ENTITY _details
                                UPDATE FIELDS ( zbankprocessedstatus zstatussync )
                                WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                               zbankprocessedstatus = 'Few Instruments are In-process.'
                                                               zstatussync = ''
                                                               ) ).
                        ENDIF.
                      ELSE.
                        DELETE processedlist WHERE z_payment_uuid EQ paymentdetail-zpaymentuuid AND z_statuscode NE 'U'.

                        IF processedlist IS NOT INITIAL.
                          currentinstrument = lines( processedlist ).
                          IF currentinstrument IS NOT INITIAL.
                            IF ( totalinstrument = currentinstrument ).
                              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                                    ENTITY _details
                                    UPDATE FIELDS ( zbankprocessedstatus )
                                     WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                                   zbankprocessedstatus = 'All Instruments are Processed.'
                                                                   ) ).
                            ELSE.
                              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                                    ENTITY _details
                                    UPDATE FIELDS ( zbankprocessedstatus )
                                     WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                                   zbankprocessedstatus = 'Few Instruments are Processed.'
                                                                   ) ).
                            ENDIF.
                          ENDIF.
                        ELSE.
                          MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                         ENTITY _details
                         UPDATE FIELDS ( zbankprocessedstatus )
                         WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                        zbankprocessedstatus = 'All Instruments are Failed.'
                                                        ) ).
                        ENDIF.
                      ENDIF.
                    ENDIF.
                  ENDIF.
                ENDIF.
              ELSE.
                MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                            ENTITY _details
                            UPDATE FIELDS ( zstatussync )
                            WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky zstatussync = '' ) ).
              ENDIF.


              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_statuslog
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_decrypt zresponsecode = statuscode_status
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.

            ELSE.
              MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_statuslog
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_status zresponsecode = statuscode_status
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.
            ENDIF.

          ELSE.
            MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_statuslog
              FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                            %target = VALUE #( ( %cid = 'logdetails' zresponse = lv_json_getrefreshtoken zresponsecode = statuscode_getrefreshtoken
                            %control = VALUE #( zresponse = if_abap_behv=>mk-on zresponsecode = if_abap_behv=>mk-on ) ) ) ) )
                            MAPPED mapped
                            FAILED failed
                            REPORTED reported.

          ENDIF.

        CATCH cx_http_dest_provider_error.
          " handle exception here.

        CATCH cx_web_http_client_error.
          " handle exception here
      ENDTRY.
    ELSE.
      MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                    ENTITY _details
                    UPDATE FIELDS ( zstatussync zbankprocessedstatus )
                    WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky zstatussync = 'X' zbankprocessedstatus = 'All Instruments are Failed.' ) ).
    ENDIF.

  ENDMETHOD.

  METHOD encrypt.
    "Get key ID.
    DATA(key_with_id) = keys.

    "Read and Update The Key details.
    READ ENTITIES OF zr_paymentdetails IN LOCAL MODE
    ENTITY _details
    FIELDS ( zpaymentuuid zpaymentfilereference zfilecontent zpaymentsync zpaymentstatus )
    WITH CORRESPONDING #( key_with_id )
    RESULT DATA(paymentdetails).

    DATA xs TYPE string.
    DATA xstring TYPE xstring.

    LOOP AT paymentdetails INTO DATA(paymentdetail).
      IF paymentdetail-zfilecontent IS NOT INITIAL.
        xs = paymentdetail-zfilecontent.
        xstring = xs.
      ENDIF.
    ENDLOOP.

    IF paymentdetail-zencryptedfile IS INITIAL AND xs IS NOT INITIAL.

      TRY.

          "API call for Post for Encrypt Details.
          DATA(loo_destination_encrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                 comm_scenario  = 'ZENCRYPTION_SC'
                               ).
          DATA(loo_http_client_encrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_encrypt ).

          DATA(loo_request_encrypt) = loo_http_client_encrypt->get_http_request( ).

          loo_request_encrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).

          DATA bodycontent TYPE string.

          bodycontent = '{ "x_string" : "' && xs && '" }'.

          loo_request_encrypt->set_text( bodycontent ).

          DATA(lo_response_encrypt) = loo_http_client_encrypt->execute( if_web_http_client=>post ).

          "Result
          DATA(lv_json_encrypt) = lo_response_encrypt->get_text( ).

          "Get Status.
          DATA(statuscode_encrypt) = lo_response_encrypt->get_status( )-code.

          IF ( statuscode_encrypt = 200 ).
            "Extract Response Details.
            DATA:
              BEGIN OF encryption_tags,
                statuscode TYPE string,
                body       TYPE string,
              END OF encryption_tags.
            /ui2/cl_json=>deserialize( EXPORTING json = lv_json_encrypt CHANGING data = encryption_tags ) .

            MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE
                 ENTITY _details
                 UPDATE FIELDS ( zencryptedfile )
                  WITH VALUE #( FOR <fs_rec_draft> IN paymentdetails ( %tky = <fs_rec_draft>-%tky
                                                zencryptedfile = encryption_tags-body
                                                ) ).
          ENDIF.

        CATCH cx_http_dest_provider_error.
          " handle exception here.

        CATCH cx_web_http_client_error.
          " handle exception here

      ENDTRY.
    ENDIF.

    "Set Instrument details into the instrument list table.

    IF xstring IS NOT INITIAL.

      DATA(conv_string) = cl_abap_conv_codepage=>create_in( )->convert( xstring ).

      DATA(decryptedxml) = cl_abap_conv_codepage=>create_out( )->convert( source = conv_string ).
      DATA(ixml_pa) = cl_ixml_core=>create( ).
      DATA(stream_factory_pa) = ixml_pa->create_stream_factory( ).
      DATA(document_pa) = ixml_pa->create_document( ).

      DATA(parser_pa) = ixml_pa->create_parser(
                         istream = stream_factory_pa->create_istream_xstring( string = decryptedxml )
                         document = document_pa
                         stream_factory = stream_factory_pa ).
      DATA(parsing_check) = parser_pa->parse( ).
      IF parsing_check = 0.
        DATA(envelope) = document_pa->get_root_element( ).
        DATA(header) = envelope->get_last_child( ).
        DATA(body) = header->get_last_child( ).
        DATA(headerlist) = body->get_first_child( ).
        DATA(instrumentlist) = body->get_last_child( ).
        DATA instrefno TYPE string.
        IF instrumentlist->get_name(  ) = 'InstrumentList'.
          DATA(instruments) = instrumentlist->get_children(  ).
          DATA(instrumentlength) = instruments->get_length(  ).
          DATA(i) = 0.
          WHILE instrumentlength > i.
            DATA(instrument) = instruments->get_item( i ).
            DATA(j) = 0.
            IF instrument->get_name( ) = 'instrument'.
              DATA(child) = instrument->get_children(  ).
              DATA(childcount) = child->get_length( ).
              WHILE childcount > j.
                DATA(childitemdata) = child->get_item( j ).
                IF childitemdata->get_name( ) = 'InstRefNo'.
                  instrefno = childitemdata->get_value( ).
                ENDIF.
                j = j + 1.
              ENDWHILE.
            ENDIF.

            DATA lv_short_time_stamp TYPE timestampl.
            GET TIME STAMP FIELD lv_short_time_stamp.

            DATA: system_uuid_log TYPE REF TO if_system_uuid,
                  uuid_log        TYPE sysuuid_c32.

            system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
            TRY.
                uuid_log = system_uuid_log->create_uuid_c32( ).
              CATCH cx_uuid_error.
            ENDTRY.

            MODIFY ENTITIES OF zr_paymentdetails IN LOCAL MODE ENTITY _details CREATE BY \_instrumentlog
                      FROM VALUE #( ( zpaymentuuid = paymentdetail-zpaymentuuid
                              %target = VALUE #( ( %cid = 'logdetails' zmessageid = instrefno
                              %control = VALUE #( zmessageid = if_abap_behv=>mk-on ) ) ) ) ).

            i = i + 1.
          ENDWHILE.
        ENDIF.
      ENDIF.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
