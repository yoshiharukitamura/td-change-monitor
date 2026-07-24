select
  filter(array[
    'lpad(col_a, 7, ''0'') as mstr__id'
    , if(col_a = '', null, 'col_a as ${sheet.replace("custom_list", "cstm")}_'||col_a)
    , if(col_b = '', null, 'col_b as ${sheet.replace("custom_list", "cstm")}_'||col_b)
    , if(col_c = '', null, 'col_c as ${sheet.replace("custom_list", "cstm")}_'||col_c)
    , if(col_d = '', null, 'col_d as ${sheet.replace("custom_list", "cstm")}_'||col_d)
    , if(col_e = '', null, 'col_e as ${sheet.replace("custom_list", "cstm")}_'||col_e)
    , if(col_f = '', null, 'col_f as ${sheet.replace("custom_list", "cstm")}_'||col_f)
    , if(col_g = '', null, 'col_g as ${sheet.replace("custom_list", "cstm")}_'||col_g)
    , if(col_h = '', null, 'col_h as ${sheet.replace("custom_list", "cstm")}_'||col_h)
    , if(col_i = '', null, 'col_i as ${sheet.replace("custom_list", "cstm")}_'||col_i)
    , if(col_j = '', null, 'col_j as ${sheet.replace("custom_list", "cstm")}_'||col_j)
    , if(col_k = '', null, 'col_k as ${sheet.replace("custom_list", "cstm")}_'||col_k)
    , if(col_l = '', null, 'col_l as ${sheet.replace("custom_list", "cstm")}_'||col_l)
    , if(col_m = '', null, 'col_m as ${sheet.replace("custom_list", "cstm")}_'||col_m)
    , if(col_n = '', null, 'col_n as ${sheet.replace("custom_list", "cstm")}_'||col_n)
    , if(col_o = '', null, 'col_o as ${sheet.replace("custom_list", "cstm")}_'||col_o)
    , if(col_p = '', null, 'col_p as ${sheet.replace("custom_list", "cstm")}_'||col_p)
    , if(col_q = '', null, 'col_q as ${sheet.replace("custom_list", "cstm")}_'||col_q)
    , if(col_r = '', null, 'col_r as ${sheet.replace("custom_list", "cstm")}_'||col_r)
    , if(col_s = '', null, 'col_s as ${sheet.replace("custom_list", "cstm")}_'||col_s)
    , if(col_t = '', null, 'col_t as ${sheet.replace("custom_list", "cstm")}_'||col_t)
    , if(col_u = '', null, 'col_u as ${sheet.replace("custom_list", "cstm")}_'||col_u)
    , if(col_v = '', null, 'col_v as ${sheet.replace("custom_list", "cstm")}_'||col_v)
    , if(col_w = '', null, 'col_w as ${sheet.replace("custom_list", "cstm")}_'||col_w)
    , if(col_x = '', null, 'col_x as ${sheet.replace("custom_list", "cstm")}_'||col_x)
    , if(col_y = '', null, 'col_y as ${sheet.replace("custom_list", "cstm")}_'||col_y)
    , if(col_z = '', null, 'col_z as ${sheet.replace("custom_list", "cstm")}_'||col_z)
  ], x -> x is not null) as cols
from
  ${sheet}
where
  col_a = 'therapist_no'
